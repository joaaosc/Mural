import AppKit

/// Abre a janela do editor de texto de onde não há cena SwiftUI para pedir: o painel da barra de menus, que é do AppKit.
///
/// A ação é registrada por `MuralCommands`, que existe mesmo sem janela aberta, com o `openWindow` do ambiente.
@MainActor
final class TextEditorOpener {
    static let shared = TextEditorOpener()

    private var action: (@MainActor () -> Void)?

    func register(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    /// Traz o Mural para a frente e abre a janela do editor. Sem ativar o app, a janela abriria atrás do app da frente: o painel
    /// de onde o pedido costuma vir não ativa o Mural. Com a janela já aberta, ela só volta para a frente, com o texto que tinha.
    /// - Returns: `false` quando ainda não há ação registrada.
    @discardableResult
    func open() -> Bool {
        guard let action else { return false }
        NSApp.activate()
        action()
        return true
    }
}
