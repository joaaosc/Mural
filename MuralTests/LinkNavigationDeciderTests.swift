import Foundation
import MuralKit
import Testing
import WebKit

@testable import Mural

/// A memória da última navegação que a pessoa pediu, sem abrir página: o decisor recebe os mesmos valores simples
/// que tira do WebKit. A parte do WebKit (clique, redirecionamento e script chegam com estes tipos de navegação) foi
/// conferida à mão com uma `WebPage` e um servidor local; aqui entra só a regra sobre ela.
@MainActor
struct LinkNavigationDeciderTests {
    private let download = URL(string: "https://example.com/baixar?id=7")!
    private let file = URL(string: "https://cdn.example.com/arquivo.zip")!
    private let other = URL(string: "https://example.com/outra")!
    private let mail = URL(string: "mailto:contato@example.com")!

    /// Uma navegação no quadro principal, do tipo dado.
    private func navigate(
        _ decider: LinkNavigationDecider, to url: URL, _ type: WKNavigationType, newWindow: Bool = false, download: Bool = false
    ) -> LinkNavigationPolicy.Decision {
        decider.decide(url: url, isMainFrame: true, opensNewWindow: newWindow, shouldDownload: download, navigationType: type)
    }

    /// A resposta do servidor a um endereço que o WebKit não sabe mostrar (um arquivo para baixar).
    private func downloadResponse(_ decider: LinkNavigationDecider, from url: URL?) -> LinkNavigationPolicy.Decision {
        decider.decide(canShowMimeType: false, url: url)
    }

    // MARK: A pessoa pediu

    @Test("Depois de clicar num link, o arquivo que ele devolve vai para o navegador")
    func clickedDownloadOpensInTheBrowser() {
        let decider = LinkNavigationDecider()

        #expect(navigate(decider, to: download, .linkActivated) == .allow)
        #expect(downloadResponse(decider, from: download) == .openExternally(download))
    }

    @Test("Enviar um formulário também conta como pedido da pessoa")
    func submittedFormCountsAsUserRequest() {
        let decider = LinkNavigationDecider()

        #expect(navigate(decider, to: download, .formSubmitted) == .allow)
        #expect(downloadResponse(decider, from: download) == .openExternally(download))
    }

    @Test("Um redirecionamento do servidor refaz a pergunta com o mesmo tipo, e o arquivo no fim da cadeia vai para o navegador")
    func downloadBehindARedirectOpensInTheBrowser() {
        let decider = LinkNavigationDecider()

        #expect(navigate(decider, to: download, .linkActivated) == .allow)
        #expect(navigate(decider, to: file, .linkActivated) == .allow)
        #expect(downloadResponse(decider, from: file) == .openExternally(file))
    }

    @Test("O http que o WebKit sobe para https, o #fragmento e a barra final não impedem de reconhecer a resposta")
    func responseMatchesDespiteIncidentalDifferences() {
        let decider = LinkNavigationDecider()
        let clicked = URL(string: "http://example.com/baixar/#topo")!
        let answered = URL(string: "https://example.com/baixar")!

        #expect(navigate(decider, to: clicked, .linkActivated) == .allow)
        #expect(downloadResponse(decider, from: answered) == .openExternally(answered))
    }

    @Test("A abertura do cartão e o tentar de novo, feitos pelo app a pedido da pessoa, também contam")
    func appLoadsRequestedByThePersonCount() {
        let decider = LinkNavigationDecider()

        decider.noteUserRequest(for: file)

        #expect(downloadResponse(decider, from: file) == .openExternally(file))
    }

    // MARK: A página fez sozinha

    @Test("Uma página que dispara um download sozinha, sem clique, tem a resposta descartada")
    func downloadWithoutAClickIsCancelled() {
        let decider = LinkNavigationDecider()

        #expect(navigate(decider, to: file, .other) == .allow, "ir para uma página da web continua permitido")
        #expect(downloadResponse(decider, from: file) == .cancel)
    }

    @Test("Uma navegação por script depois do clique não vira pedido da pessoa e não troca o que ela pediu")
    func scriptedNavigationAfterAClickIsNotTheirs() {
        let decider = LinkNavigationDecider()

        #expect(navigate(decider, to: download, .linkActivated) == .allow)
        #expect(navigate(decider, to: file, .other) == .allow)
        #expect(downloadResponse(decider, from: file) == .cancel, "o arquivo foi pedido pela página")
        #expect(downloadResponse(decider, from: download) == .openExternally(download), "o clique continua esperando a resposta dele")
    }

    @Test("A resposta de outro endereço que não o clicado é descartada")
    func responseToAnotherAddressIsCancelled() {
        let decider = LinkNavigationDecider()

        #expect(navigate(decider, to: download, .linkActivated) == .allow)
        #expect(downloadResponse(decider, from: other) == .cancel)
        #expect(downloadResponse(decider, from: nil) == .cancel)
    }

    @Test("A resposta da pessoa vale uma vez só: se a página pedir o mesmo endereço de novo, já não é dela")
    func userResponseIsUsedOnce() {
        let decider = LinkNavigationDecider()

        #expect(navigate(decider, to: download, .linkActivated) == .allow)
        #expect(downloadResponse(decider, from: download) == .openExternally(download))
        #expect(downloadResponse(decider, from: download) == .cancel)
    }

    @Test("Recarregar, voltar e avançar não são pedidos de clique")
    func reloadAndHistoryAreNotClicks() {
        let decider = LinkNavigationDecider()

        for type in [WKNavigationType.reload, .backForward, .other] {
            #expect(navigate(decider, to: download, type) == .allow)
            #expect(downloadResponse(decider, from: download) == .cancel, "\(type)")
        }
    }

    // MARK: O que sai do app não deixa pedido pendente

    @Test("Um clique que abre fora do app (janela nova, download marcado) não deixa uma resposta esperando")
    func clickThatLeavesTheAppLeavesNothingPending() {
        let decider = LinkNavigationDecider()

        #expect(navigate(decider, to: download, .linkActivated, newWindow: true) == .openExternally(download))
        #expect(downloadResponse(decider, from: download) == .cancel)

        #expect(navigate(decider, to: file, .linkActivated, download: true) == .openExternally(file))
        #expect(downloadResponse(decider, from: file) == .cancel)
    }

    @Test("A resposta que o WebKit sabe mostrar segue na página e também gasta o pedido")
    func showableResponseIsAllowedAndConsumesTheRequest() {
        let decider = LinkNavigationDecider()

        #expect(navigate(decider, to: download, .linkActivated) == .allow)
        #expect(decider.decide(canShowMimeType: true, url: download) == .allow)
        #expect(downloadResponse(decider, from: download) == .cancel)
    }

    // MARK: Esquemas de fora da web

    @Test("Só o clique manda e-mail, ligação e mensagem para o sistema; o resto fica de fora")
    func onlyClicksOpenMailAndPhoneSchemes() {
        let decider = LinkNavigationDecider()
        let app = URL(string: "slack://channel?team=T1")!

        for type in [WKNavigationType.linkActivated, .formSubmitted] {
            #expect(navigate(decider, to: mail, type) == .openExternally(mail))
            #expect(navigate(decider, to: app, type) == .cancel)
        }
        #expect(navigate(decider, to: mail, .other) == .cancel, "a página não abre outro app sozinha")
        #expect(navigate(decider, to: mail, .reload) == .cancel)
    }
}
