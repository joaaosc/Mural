import MuralKit
import SwiftUI
import WebKit

/// Nível 3 de um cartão de link: a página real, navegável, dentro do app.
///
/// Segue a orientação da Apple para páginas dentro do app (acesso breve, sem virar um navegador): não há barra de
/// endereço nem abas, só página anterior, próxima e recarregar na pílula, uma barra fina de progresso e, se a página
/// não abrir, uma tela com o cartão e as saídas. Só uma `WebPage` existe por vez: ela nasce quando o detalhe aparece
/// e para quando ele sai.
struct LinkDetailView: View {
    let item: BoardItem
    let model: BoardModel
    /// De onde vem a página. Nos testes de interface é um HTML local de exemplo, sem rede.
    var source: LinkPageController.Source = LaunchConfiguration.loadsLivePages() ? .web : .html(FixtureLinkPage.html)
    /// Pede a confirmação de apagar, a mesma das outras telas de detalhe.
    var onRequestDelete: () -> Void

    @Environment(\.linkPreviewFiles) private var files
    @State private var controller = LinkPageController()

    var body: some View {
        pageArea
            .padding(.horizontal, 48)
            .padding(.top, 70)
            .padding(.bottom, 80)
            .overlay(alignment: .bottom) {
                LinkActionPill(actions: pillActions)
                    .padding(.bottom, 22)
            }
            .onAppear { controller.start(url: item.browserURL, source: source) }
            .onDisappear { controller.stop() }
    }

    // MARK: Página

    private var pageArea: some View {
        ZStack {
            if let page = controller.page {
                WebView(page)
                    .webViewBackForwardNavigationGestures(.enabled)
                    .webViewMagnificationGestures(.enabled)
                    .webViewLinkPreviews(.enabled)
                    .allowsHitTesting(controller.failure == nil)
                    .accessibilityHidden(controller.failure != nil)
            }
            if let failure = controller.failure {
                LinkFailureView(
                    item: item, message: failure.message, files: files,
                    onRetry: controller.retry, onOpenInBrowser: controller.openInBrowser)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.page)
        .overlay(alignment: .top) {
            if let page = controller.page, page.isLoading {
                ProgressView(value: min(max(page.estimatedProgress, 0), 1))
                    .progressViewStyle(ThinBarProgressStyle())
                    .accessibilityLabel("Carregando a página")
                    .transition(.opacity)
            }
        }
        .animation(.default, value: controller.page?.isLoading)
        .clipShape(.rect(cornerRadius: Theme.mediaCorner))
        // O recorte da prévia sai do tamanho da área da página.
        .onGeometryChange(for: CGSize.self, of: \.size) { controller.viewportSize = $0 }
    }

    // MARK: Pílula

    private var pillActions: [LinkActionPill.Action] {
        [
            .init(title: "Página anterior", symbol: "chevron.backward", isEnabled: controller.canGoBack, perform: controller.goBack),
            .init(title: "Próxima página", symbol: "chevron.forward", isEnabled: controller.canGoForward, perform: controller.goForward),
            .init(title: "Recarregar", symbol: "arrow.clockwise", isEnabled: controller.page != nil, perform: controller.reload),
            .init(
                title: "Abrir no navegador", symbol: "safari", isEnabled: controller.browserURL != nil,
                perform: controller.openInBrowser),
            .init(
                title: "Copiar link", symbol: "link", isEnabled: controller.browserURL != nil,
                perform: { controller.copyLink(of: item, from: model) }),
            .init(
                title: "Usar como prévia", symbol: controller.previewState == .saved ? "checkmark" : "camera.viewfinder",
                isEnabled: controller.canUseAsPreview && files != nil,
                perform: {
                    guard let files else { return }
                    controller.usePageAsPreview(itemID: item.id, in: model, files: files)
                }),
            .init(title: "Apagar", symbol: "trash", role: .destructive, perform: onRequestDelete),
        ]
    }
}

/// Barra de progresso de 2 pontos, no topo da página.
private struct ThinBarProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        Rectangle()
            .fill(.tint)
            .frame(height: 2)
            // Nunca fica vazia: logo ao começar já mostra que algo está carregando.
            .scaleEffect(x: max(configuration.fractionCompleted ?? 0, 0.04), y: 1, anchor: .leading)
            .animation(.linear(duration: 0.2), value: configuration.fractionCompleted)
    }
}
