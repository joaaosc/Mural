import AppKit

/// Como o painel foi pedido.
///
/// Ancorado: a partir do ícone da barra de menus, pendurado nele. Centralizado: no meio da tela sob o ponteiro, para
/// um pedido que não nasce do ícone (o menu do app).
nonisolated struct MenuBarPresentation: Equatable, Sendable {
    static let anchored = MenuBarPresentation(isCentered: false)
    static let centered = MenuBarPresentation(isCentered: true)

    let isCentered: Bool
}

/// O ícone do Mural na barra de menus e o painel que ele abre.
///
/// O ícone usa a sessão de interface expandida do macOS 27 (`NSStatusItemExpandedInterfaceDelegate`), e não um
/// target/action no botão: o sistema avisa quando a interface deve abrir e fechar, e o ícone participa da navegação por
/// teclado e do acompanhamento de menus da barra. O painel é do AppKit, e não de uma `MenuBarExtra`, porque também
/// precisa abrir por código (o item "Abrir Painel de Murais" do menu).
///
/// A pessoa pode arrastar o painel pelo fundo; o lugar fica guardado (`MenuBarPanelPosition`) e vale para as próximas
/// aberturas, pelo ícone ou não.
@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    /// A distância entre o botão do ícone e o topo do painel ancorado.
    private nonisolated static let anchorGap: CGFloat = 6
    /// A margem que o painel ancorado mantém das bordas da área visível da tela.
    private nonisolated static let screenEdgeMargin: CGFloat = 8
    /// A área visível de quando nenhuma tela responde (não deveria acontecer).
    private static let fallbackVisibleFrame = NSRect(x: 0, y: 0, width: 1280, height: 800)

    private var statusItem: NSStatusItem?
    private var panel: MenuBarPanel?
    /// Guardado porque uma janela não retém o próprio delegate.
    private var dismissMonitor: PanelDismissMonitor?
    /// Como o painel está na tela agora; `nil` com ele fora da tela.
    private var presentation: MenuBarPresentation?
    private var isFitScheduled = false
    private var makeContent: (@MainActor (MenuBarPresentation) -> NSView)?
    /// Onde a pessoa deixou o painel da última vez.
    private let position = MenuBarPanelPosition.shared

    private override init() {
        super.init()
    }

    var isPresented: Bool { panel?.isVisible == true }

    /// Guarda como montar o conteúdo do painel. Não cria o ícone: quem decide se esta cópia do Mural o mostra é o
    /// `MenuBarIconCoordinator`, por `setStatusItemVisible(_:)`. Uma segunda chamada só troca o construtor.
    ///
    /// - Parameter content: monta o conteúdo do painel para uma apresentação. É chamado a cada apresentação, e não uma
    ///   vez, para o conteúdo nascer com o estado do instante em que o painel abre.
    func install(content: @escaping @MainActor (MenuBarPresentation) -> NSView) {
        makeContent = content
    }

    /// Põe o ícone na barra de menus ou o tira de lá. Pode ser chamado quantas vezes for: pedir o que já está assim não
    /// faz nada.
    ///
    /// Sem o ícone, `presentCentered()` continua abrindo o painel no meio da tela.
    func setStatusItemVisible(_ visible: Bool) {
        if visible {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "Mural")
            item.button?.toolTip = "Mural"
            item.expandedInterfaceDelegate = self
            statusItem = item
        } else {
            guard let item = statusItem else { return }
            // O painel ancorado pende do ícone e sai com ele; o centralizado não depende do ícone e fica.
            if presentation == .anchored { dismiss() }
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    /// Abre o painel no meio da tela sob o ponteiro, para um pedido que não nasce do ícone (o menu do app).
    func presentCentered() {
        // Uma sessão ancorada aberta é encerrada antes. O fim dela pode chegar depois de o painel centralizado já estar
        // na tela, e `statusItemDidEndExpandedInterfaceSession` ignora o que não é ancorado.
        statusItem?.expandedInterfaceSession?.cancel()
        show(.centered)
    }

    /// Fecha o painel. Pode ser chamado a qualquer hora, quantas vezes for.
    ///
    /// Ancorado, a sessão do ícone é encerrada junto, para o ícone e o painel não discordarem sobre estar aberto. O
    /// painel sai da tela na hora, sem depender do fim de sessão que o AppKit avisa depois do `cancel()`: quando o aviso
    /// chega, não há mais nada a fechar.
    func dismiss() {
        if presentation == .anchored {
            statusItem?.expandedInterfaceSession?.cancel()
        }
        hide()
    }

    /// Ajusta o painel aberto ao que o conteúdo pede agora, mantendo a borda de cima onde está: um menu cresce para
    /// baixo a partir de onde pende.
    ///
    /// Chamado pelo conteúdo quando a altura dele muda. O vidro não passa o tamanho do conteúdo para a janela (ver
    /// `GlassHostingView`), então nada redimensiona o painel por trás do controlador. Adiado uma volta, para a medida
    /// nunca rodar dentro da atualização do SwiftUI que a pediu.
    func fitToContent() {
        // Um ajuste pendente basta: várias mudanças de altura na mesma volta são respondidas pela medida de quando ele
        // rodar.
        guard !isFitScheduled else { return }
        isFitScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            isFitScheduled = false
            guard let panel, panel.isVisible, let content = panel.contentView else { return }
            let size = Self.contentSize(of: content)
            guard size != panel.frame.size else { return }
            var frame = Self.frame(keepingTopOf: panel.frame, size: size)
            // Arrastado para perto da base da tela, o painel que cresce sobe o necessário para não sair dela.
            if let visibleFrame = panel.screen?.visibleFrame {
                frame = MenuBarPanelPlacement.clamped(frame, to: visibleFrame)
            }
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
        }
    }

    /// Guarda onde a pessoa deixou o painel, para ele abrir ali da próxima vez. Chamado pelo conteúdo quando um arrasto
    /// do painel termina; só um arrasto da pessoa chega aqui, nunca uma mudança de lugar feita por código.
    func panelWasMoved() {
        guard let panel, panel.isVisible else { return }
        position.save(topLeft: MenuBarPanelPlacement.topLeft(of: panel.frame))
    }

    // MARK: Tamanho e posição

    /// O que o conteúdo pede na largura do painel.
    ///
    /// A largura é fixa (o painel não se redimensiona na horizontal), então só a altura é de fato medida. Uma árvore
    /// hospedada no vidro devolve zero em `fittingSize` (a hospedagem não tem opções de tamanho), e por isso é medida
    /// por `PanelContentMeasuring`; qualquer outra vista ainda responde `fittingSize`. Resposta zero cai na altura
    /// mínima em vez de abrir um painel que ninguém vê. A altura passa no máximo do teto.
    static func contentSize(of content: NSView) -> NSSize {
        let width = PanelMetrics.panelWidth
        let measured = (content as? PanelContentMeasuring)?.idealSize(forWidth: width) ?? content.fittingSize
        guard measured.width > 0, measured.height > 0 else {
            return NSSize(width: width, height: PanelMetrics.minimumHeight)
        }
        return NSSize(width: width, height: min(measured.height.rounded(.up), PanelMetrics.maximumHeight))
    }

    /// `frame` com o tamanho `size` e a borda de cima no mesmo lugar.
    static func frame(keepingTopOf frame: NSRect, size: NSSize) -> NSRect {
        NSRect(
            x: frame.minX,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// `size` centralizado em `visibleFrame`.
    nonisolated static func centeredFrame(size: NSSize, in visibleFrame: NSRect) -> NSRect {
        NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Onde o painel pende do ícone: a borda direita alinhada à do botão e o topo 6 pt abaixo dele, preso à área visível
    /// com 8 pt de margem. Sem o botão (raro), no canto superior direito da área visível.
    ///
    /// A margem do alto não empurra o painel para baixo: o topo fica a 6 pt do botão, e só nunca passa da borda de cima
    /// da área visível (a barra de menus).
    nonisolated static func anchoredFrame(size: NSSize, belowButton buttonFrame: NSRect?, in visibleFrame: NSRect) -> NSRect {
        let limits = visibleFrame.insetBy(dx: screenEdgeMargin, dy: screenEdgeMargin)
        let right = buttonFrame?.maxX ?? visibleFrame.maxX
        let top = (buttonFrame?.minY ?? visibleFrame.maxY) - anchorGap
        let x = min(max(right - size.width, limits.minX), max(limits.minX, limits.maxX - size.width))
        let y = min(max(top - size.height, limits.minY), visibleFrame.maxY - size.height)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// A área visível da tela em que o ponteiro está, ou a da tela principal.
    private static func pointerScreenVisibleFrame() -> NSRect {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(pointer) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? fallbackVisibleFrame
    }

    /// A moldura ancorada ao botão do ícone, ou ao canto da tela principal quando o botão ainda não tem janela.
    private func anchoredFrame(size: NSSize) -> NSRect {
        guard let button = statusItem?.button, let window = button.window else {
            let visibleFrame = NSScreen.main?.visibleFrame ?? Self.fallbackVisibleFrame
            return Self.anchoredFrame(size: size, belowButton: nil, in: visibleFrame)
        }
        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame ?? Self.fallbackVisibleFrame
        return Self.anchoredFrame(size: size, belowButton: buttonFrame, in: visibleFrame)
    }

    // MARK: Painel

    /// Mostra o painel com um conteúdo novo. Não ativa o app: o painel não traz a janela do Mural para a frente.
    private func show(_ presentation: MenuBarPresentation) {
        guard let makeContent else { return }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        self.presentation = presentation

        let content = makeContent(presentation)
        panel.contentView = content
        let size = Self.contentSize(of: content)
        // Onde a pessoa deixou o painel vale mais que o lugar de sempre, enquanto aquela tela estiver ligada.
        let remembered = position.topLeftToRestore.flatMap { topLeft in
            MenuBarPanelPlacement.frame(size: size, topLeft: topLeft, visibleFrames: NSScreen.screens.map(\.visibleFrame))
        }
        let frame =
            remembered
            ?? (presentation.isCentered
                ? Self.centeredFrame(size: size, in: Self.pointerScreenVisibleFrame())
                : anchoredFrame(size: size))
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()

        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func hide() {
        panel?.orderOut(nil)
        presentation = nil
    }

    private func makePanel() -> MenuBarPanel {
        let panel = MenuBarPanel(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(width: PanelMetrics.panelWidth, height: PanelMetrics.minimumHeight)
            )
        )
        panel.identifier = NSUserInterfaceItemIdentifier("mural-menu-bar-panel")
        panel.title = "Mural"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false

        // Este painel sempre fecha quando o usuário clica fora: não é uma janela para deixar ao lado do trabalho.
        let monitor = PanelDismissMonitor(
            isEnabled: { true },
            dismiss: { [weak self] in self?.dismiss() }
        )
        panel.delegate = monitor
        dismissMonitor = monitor
        panel.onCancel = { [weak self] in self?.dismiss() }
        return panel
    }
}

extension MenuBarController: @MainActor NSStatusItemExpandedInterfaceDelegate {
    func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        show(.anchored)
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        // Só a apresentação ancorada acaba com a sessão. Um painel centralizado aberto depois não pode ser fechado por
        // um fim de sessão que chegou atrasado.
        guard presentation == .anchored else { return }
        hide()
    }
}
