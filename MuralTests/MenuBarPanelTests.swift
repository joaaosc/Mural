import AppKit
import SwiftUI
import Testing

@testable import Mural

/// O painel da barra de menus: a medida do conteúdo, a posição, a placa de acessibilidade e quando ele fecha.
@Suite("Painel da barra de menus")
@MainActor
struct MenuBarPanelTests {
    private struct FixedContent: View {
        var body: some View {
            Color.clear.frame(width: 320, height: 180)
        }
    }

    private typealias Surface = PanelGlassSurface<EmptyView>

    // MARK: Medida do conteúdo

    @Test("O conteúdo hospedado é medido mesmo com fittingSize quase zero")
    func measuresHostedContent() {
        let host = GlassHostingView(rootView: FixedContent())

        #expect(host.fittingSize.height < 20)
        #expect(host.idealSize(forWidth: 320) == CGSize(width: 320, height: 180))
    }

    @Test("O vidro é o regular, sem tinta própria")
    func usesPlainRegularGlass() {
        let host = GlassHostingView(rootView: FixedContent(), cornerRadius: 22)

        #expect(host.style == .regular)
        #expect(host.tintColor == nil)
        #expect(host.cornerRadius == 22)
        #expect(host.contentView != nil)
    }

    @Test("O painel tem a largura fixa e a altura medida do conteúdo hospedado")
    func usesFixedWidthAndMeasuredHeight() {
        let host = GlassHostingView(rootView: Color.clear.frame(height: 240))

        let size = MenuBarController.contentSize(of: host)

        #expect(size == NSSize(width: PanelMetrics.panelWidth, height: 240))
    }

    @Test("Conteúdo sem tamanho cai na altura mínima, para o painel continuar visível")
    func emptyContentFallsBackToMinimumHeight() {
        let size = MenuBarController.contentSize(of: NSView())

        #expect(size == NSSize(width: PanelMetrics.panelWidth, height: PanelMetrics.minimumHeight))
    }

    @Test("A altura do conteúdo não passa do teto")
    func heightIsCapped() {
        let host = GlassHostingView(rootView: Color.clear.frame(height: PanelMetrics.maximumHeight + 400))

        let size = MenuBarController.contentSize(of: host)

        #expect(size == NSSize(width: PanelMetrics.panelWidth, height: PanelMetrics.maximumHeight))
    }

    // MARK: Posição

    @Test("Redimensionar mantém a borda de cima onde o painel pende")
    func resizeKeepsTopEdge() {
        let frame = NSRect(x: 100, y: 500, width: 600, height: 200)

        let grown = MenuBarController.frame(keepingTopOf: frame, size: NSSize(width: 600, height: 320))

        #expect(grown.maxY == frame.maxY)
        #expect(grown.minX == frame.minX)
        #expect(grown.height == 320)
    }

    @Test("O painel centralizado fica no meio da área visível")
    func centersInVisibleFrame() {
        let visible = NSRect(x: 0, y: 25, width: 1440, height: 875)

        let frame = MenuBarController.centeredFrame(size: NSSize(width: 400, height: 300), in: visible)

        #expect(frame.size == NSSize(width: 400, height: 300))
        #expect(frame.midX == visible.midX)
        #expect(frame.midY == visible.midY)
    }

    @Test("Uma tela com origem negativa mantém o deslocamento ao centralizar")
    func centersOnScreenWithNegativeOrigin() {
        let visible = NSRect(x: -1920, y: 100, width: 1920, height: 1000)

        let frame = MenuBarController.centeredFrame(size: NSSize(width: 420, height: 500), in: visible)

        #expect(frame.origin == NSPoint(x: -1920 + 750, y: 350))
    }

    @Test("A apresentação centralizada não é a ancorada")
    func centeredPresentationIsDistinct() {
        #expect(MenuBarPresentation.centered.isCentered)
        #expect(!MenuBarPresentation.anchored.isCentered)
        #expect(MenuBarPresentation.centered != .anchored)
    }

    @Test("Ancorado, o painel alinha a borda direita à do botão e fica 6 pt abaixo dele")
    func anchoredBelowTheButton() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 876)
        let button = NSRect(x: 1200, y: 876, width: 30, height: 24)
        let size = NSSize(width: 600, height: 200)

        let frame = MenuBarController.anchoredFrame(size: size, belowButton: button, in: visible)

        #expect(frame.size == size)
        #expect(frame.maxX == button.maxX)
        #expect(frame.maxY == button.minY - 6)
    }

    @Test("Ancorado junto à borda da tela, o painel guarda a margem de 8 pt")
    func anchoredKeepsTheScreenMargin() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 876)
        let size = NSSize(width: 600, height: 200)
        let nearRight = NSRect(x: 1410, y: 876, width: 28, height: 24)
        let nearLeft = NSRect(x: 0, y: 876, width: 30, height: 24)

        let right = MenuBarController.anchoredFrame(size: size, belowButton: nearRight, in: visible)
        let left = MenuBarController.anchoredFrame(size: size, belowButton: nearLeft, in: visible)

        #expect(right.maxX == visible.maxX - 8)
        #expect(left.minX == visible.minX + 8)
    }

    @Test("Sem o botão do ícone, o painel vai para o canto superior direito")
    func anchoredWithoutButton() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 876)

        let frame = MenuBarController.anchoredFrame(size: NSSize(width: 600, height: 200), belowButton: nil, in: visible)

        #expect(frame.maxX == visible.maxX - 8)
        #expect(frame.maxY == visible.maxY - 6)
    }

    // MARK: Placa de acessibilidade

    @Test("Sem placa em repouso; Reduzir Transparência a torna opaca e Aumentar Contraste, quase")
    func plateOpacityFollowsAccessibility() {
        #expect(Surface.plateOpacity(reduceTransparency: false, contrast: .standard) == 0)
        #expect(Surface.plateOpacity(reduceTransparency: false, contrast: .increased) == 0.85)
        #expect(Surface.plateOpacity(reduceTransparency: true, contrast: .standard) == 1)
        #expect(Surface.plateOpacity(reduceTransparency: true, contrast: .increased) == 1)
    }

    // MARK: Fechar ao clicar fora

    @Test("Um clique fora fecha o painel")
    func closesOnAnOutsideClick() {
        #expect(PanelDismissMonitor.shouldDismiss(context()))
    }

    @Test("Um painel que já saiu da tela não é fechado de novo")
    func ignoresAHiddenPanel() {
        #expect(!PanelDismissMonitor.shouldDismiss(context { $0.isPanelVisible = false }))
    }

    @Test("Uma folha aberta pelo painel não é um clique fora dele")
    func keepsThePanelUnderItsOwnSheet() {
        #expect(!PanelDismissMonitor.shouldDismiss(context { $0.hasAttachedSheet = true }))
    }

    @Test("Uma janela do próprio painel também não")
    func keepsThePanelUnderItsOwnWindows() {
        #expect(!PanelDismissMonitor.shouldDismiss(context { $0.keyWindowBelongsToPanel = true }))
    }

    @Test("O seletor de cores e o painel de salvar também não")
    func keepsThePanelUnderASystemPanel() {
        #expect(!PanelDismissMonitor.shouldDismiss(context { $0.keyWindowIsSystemPanel = true }))
    }

    // MARK: Apoio

    /// Um clique em outra coisa, com o painel visível: o caso que fecha. Cada teste muda só o que importa a ele.
    private func context(_ change: (inout PanelDismissContext) -> Void = { _ in }) -> PanelDismissContext {
        var context = PanelDismissContext(
            closesOnOutsideClick: true,
            isPanelVisible: true,
            hasAttachedSheet: false,
            keyWindowBelongsToPanel: false,
            keyWindowIsSystemPanel: false
        )
        change(&context)
        return context
    }
}
