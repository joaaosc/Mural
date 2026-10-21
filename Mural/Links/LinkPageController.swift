import AppKit
import MuralKit
import Observation
import SwiftUI
import WebKit

/// A página da web de um cartão de link: cria a `WebPage` quando o detalhe aparece, acompanha as navegações
/// (erro, histórico, progresso) e oferece as ações da pílula.
///
/// Há uma por detalhe aberto e ela só existe enquanto o detalhe existe: `stop()` interrompe o carregamento e
/// pausa a mídia ao sair, e a página some junto com o controlador.
@MainActor
@Observable
final class LinkPageController {
    /// De onde vem o conteúdo da página.
    enum Source: Equatable {
        /// A página do cartão, pela rede.
        case web
        /// HTML local (testes de interface e prévias do Xcode), sem rede: o endereço do cartão serve só de base.
        case html(String)
    }

    /// Por que a página não abriu.
    struct Failure: Equatable {
        let message: String
        /// O endereço que falhou, para tentar de novo; `nil` se nem havia endereço.
        let url: URL?
    }

    /// Andamento de "Usar como prévia".
    enum PreviewState: Equatable {
        case idle
        case capturing
        /// Acabou de gravar: a pílula mostra um `checkmark` por um instante.
        case saved
    }

    private enum PreviewError: Error {
        case unreadableImage
    }

    /// Largura, em pontos, da imagem capturada: a mesma do maior lado que `LinkPreviewFiles` guarda.
    private static let snapshotWidth: CGFloat = 800
    private static let savedFeedbackDuration = Duration.milliseconds(1_500)
    private static let previewFailureMessage = "Não foi possível usar a página como prévia."

    /// A página viva; `nil` até `start(url:source:)` e quando o cartão não tem endereço da web.
    private(set) var page: WebPage?
    private(set) var failure: Failure?
    private(set) var previewState = PreviewState.idle

    /// Tamanho da área da página. O recorte da prévia sai dele. Muda a cada ajuste da janela, então a tela não o observa.
    @ObservationIgnored var viewportSize = CGSize.zero

    @ObservationIgnored private var entryURL: URL?
    @ObservationIgnored private var source = Source.web
    @ObservationIgnored private var lastRequestedURL: URL?
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private var feedbackTask: Task<Void, Never>?

    // MARK: Ciclo de vida

    /// Cria a página e começa a carregar. Só vale na primeira chamada.
    /// - Parameter url: o endereço do cartão (`nil` se não for da web: aparece a tela de erro, sem tentar carregar).
    func start(url: URL?, source: Source) {
        guard page == nil, failure == nil else { return }
        guard let url else {
            failure = Failure(message: "O endereço deste cartão não é de uma página da web.", url: nil)
            return
        }
        entryURL = url
        self.source = source

        var configuration = WebPage.Configuration()
        // Nada fica gravado em disco (cookies, cache): a página é para uma consulta rápida, não um perfil de navegação.
        configuration.websiteDataStore = .nonPersistent()
        let page = WebPage(configuration: configuration, navigationDecider: LinkNavigationDecider())
        self.page = page
        observeNavigations(of: page)
        load()
    }

    /// Interrompe o carregamento e pausa a mídia: a página não toca nem baixa nada depois que o detalhe sai.
    func stop() {
        observer?.cancel()
        observer = nil
        feedbackTask?.cancel()
        feedbackTask = nil
        guard let page else { return }
        page.stopLoading()
        Task { await page.pauseAllMediaPlayback() }
    }

    // MARK: Carregamento

    private func load() {
        guard let page, let entryURL else { return }
        switch source {
        case .web:
            lastRequestedURL = entryURL
            page.load(URLRequest(url: entryURL))
        case .html(let html):
            page.load(html: html, baseURL: entryURL)
        }
    }

    /// Tenta de novo o que falhou (ou o endereço do cartão). A tela de erro continua até a página começar a chegar.
    func retry() {
        guard let page else { return }
        switch source {
        case .web:
            guard let url = failure?.url ?? entryURL else { return }
            lastRequestedURL = url
            page.load(URLRequest(url: url))
        case .html:
            load()
        }
    }

    func reload() {
        guard let page else { return }
        if failure != nil || page.url == nil {
            retry()
        } else {
            page.reload()
        }
    }

    // MARK: Histórico

    var canGoBack: Bool { page.map { !$0.backForwardList.backList.isEmpty } ?? false }
    var canGoForward: Bool { page.map { !$0.backForwardList.forwardList.isEmpty } ?? false }

    /// Volta à página anterior do histórico (a lista vem da mais antiga para a mais recente).
    func goBack() {
        guard let page, let item = page.backForwardList.backList.last else { return }
        page.load(item)
    }

    func goForward() {
        guard let page, let item = page.backForwardList.forwardList.first else { return }
        page.load(item)
    }

    // MARK: Acompanhamento das navegações

    /// Acompanha todas as navegações, inclusive as que a pessoa faz clicando nos links da página.
    private func observeNavigations(of page: WebPage) {
        // A sequência só registra o que acontece depois de criada: criá-la antes do primeiro carregamento
        // garante que uma falha logo de início não passe batida.
        let initial = page.navigations
        observer = Task { [weak self, weak page] in
            var events = initial
            while !Task.isCancelled {
                do {
                    for try await event in events {
                        self?.handle(event)
                    }
                    return
                } catch {
                    // Uma falha encerra a sequência: depois de registrá-la, é preciso assinar de novo.
                    guard !Task.isCancelled, let page else { return }
                    self?.handle(error)
                    events = page.navigations
                }
            }
        }
    }

    private func handle(_ event: WebPage.NavigationEvent) {
        switch event {
        case .committed:
            failure = nil
        case .startedProvisionalNavigation, .receivedServerRedirect, .finished:
            break
        @unknown default:
            break
        }
    }

    private func handle(_ error: any Error) {
        guard let error = error as? WebPage.NavigationError else { return }
        switch error {
        case .failedProvisionalNavigation(let underlying):
            guard !Self.isCancellation(underlying) else { return }
            failure = Failure(message: underlying.localizedDescription, url: Self.failingURL(of: underlying) ?? lastRequestedURL)
        case .webContentProcessTerminated:
            failure = Failure(message: "A página parou de responder.", url: lastRequestedURL ?? entryURL)
        case .invalidURL:
            failure = Failure(message: "O endereço da página não é válido.", url: nil)
        case .pageClosed:
            break
        @unknown default:
            break
        }
    }

    /// Navegação que o app mesmo interrompeu (abriu o endereço fora, ou a pessoa clicou em outro link antes de
    /// terminar): não é falha da página.
    static func isCancellation(_ error: any Error) -> Bool {
        let error = error as NSError
        switch (error.domain, error.code) {
        case (NSURLErrorDomain, NSURLErrorCancelled):
            return true
        case ("WebKitErrorDomain", 102):  // carregamento interrompido por mudança de política
            return true
        default:
            return false
        }
    }

    private static func failingURL(of error: any Error) -> URL? {
        (error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL
    }

    // MARK: Navegador e área de transferência

    /// O endereço da web que a pessoa está vendo (ou tentando ver); sem ele, o do cartão.
    var browserURL: URL? {
        if let failed = failure?.url, WebLink.isWeb(failed) { return failed }
        if failure == nil, let current = page?.url, WebLink.isWeb(current) { return current }
        return entryURL
    }

    func openInBrowser() {
        guard let url = browserURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Copia o endereço da página atual, com o título do cartão (ou o da página, se a pessoa já foi para outra).
    func copyLink(of item: BoardItem, from model: BoardModel) {
        guard let url = browserURL else { return }
        var shown = item
        shown.link?.url = url
        if url != item.link?.url, let title = page?.title, !title.isEmpty {
            shown.title = title
        }
        PasteboardExporter.copy(shown, from: model)
    }

    // MARK: Prévia do cartão

    var canUseAsPreview: Bool { page != nil && failure == nil && previewState != .capturing }

    /// Tira uma foto do que se vê na página e a grava como imagem de prévia do cartão. Se algo falhar, avisa e
    /// o cartão fica como estava.
    func usePageAsPreview(itemID: UUID, in model: BoardModel, files: LinkPreviewFiles) {
        guard canUseAsPreview, let page else { return }
        guard let region = LinkPreviewCrop.region(inViewportOf: viewportSize, aspectRatio: LinkCard.imageAspectRatio) else {
            model.lastError = Self.previewFailureMessage
            return
        }

        previewState = .capturing
        Task {
            do {
                let data = try await page.exported(as: .image(region: .rect(region), snapshotWidth: Self.snapshotWidth))
                guard let name = try await Self.storePreviewImage(data, itemID: itemID, files: files) else {
                    throw PreviewError.unreadableImage
                }
                model.applyLinkPreviews([LinkPreviewUpdate(itemID: itemID, previewImageFile: name, state: .ready(fetchedAt: .now))])
                showSaved()
            } catch {
                previewState = .idle
                model.lastError = Self.previewFailureMessage
            }
        }
    }

    /// Reduz e grava a imagem fora da thread principal. `nil` se os dados não forem uma imagem aceita.
    @concurrent
    private nonisolated static func storePreviewImage(_ data: Data, itemID: UUID, files: LinkPreviewFiles) async throws -> String? {
        try files.store(imageData: data, iconData: nil, for: itemID).image
    }

    private func showSaved() {
        previewState = .saved
        AccessibilityNotification.Announcement("Prévia do cartão atualizada").post()
        feedbackTask?.cancel()
        feedbackTask = Task {
            try? await Task.sleep(for: Self.savedFeedbackDuration)
            guard !Task.isCancelled else { return }
            previewState = .idle
        }
    }
}
