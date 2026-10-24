import AppKit

/// O painel que o ícone da barra de menus abre.
///
/// Sem borda e sem ativar o app: abrir o painel não traz a janela do Mural para a frente, mas ele pode ser a janela
/// key, para receber teclado e atalhos.
final class MenuBarPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // O arrasto pelo fundo é do conteúdo (`WindowDragGesture`), que avisa quando termina para o lugar ser guardado.
        // Pelo AppKit, qualquer clique no fundo poderia mover o painel sem esse aviso.
        isMovableByWindowBackground = false
        // A barra de menus pertence ao Space em que o usuário está.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// O que o Esc faz quando nenhuma vista do conteúdo trata a tecla: o controlador fecha o painel e encerra a sessão
    /// do ícone. Sem isto, o `NSPanel` se fecharia sozinho e o ícone continuaria achando que o painel está aberto.
    var onCancel: (@MainActor () -> Void)?

    override func cancelOperation(_ sender: Any?) {
        if let onCancel {
            onCancel()
        } else {
            super.cancelOperation(sender)
        }
    }

    /// ⌘V vira o pedido de colar do conteúdo.
    ///
    /// O painel não ativa o app, então o atalho do item Colar do menu Editar pode não chegar até ele. Assim o ⌘V
    /// dentro do painel sobe pela cadeia de respostas como um `paste:` comum.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // O Caps Lock não conta como modificador de atalho.
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "v",
            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
        {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
