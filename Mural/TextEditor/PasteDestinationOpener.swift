import AppKit

/// Abre a janela "Colar no mural" de onde não há cena SwiftUI para pedir. A ação é registrada por `MuralCommands`, que existe
/// mesmo sem janela aberta, com o `openWindow` do ambiente (como `TextEditorOpener`).
@MainActor
final class PasteDestinationOpener {
    static let shared = PasteDestinationOpener()

    private var action: (@MainActor () -> Void)?

    func register(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    /// Traz o Mural para a frente e abre a galeria.
    /// - Returns: `false` quando ainda não há ação registrada.
    @discardableResult
    func open() -> Bool {
        guard let action else { return false }
        NSApp.activate()
        action()
        return true
    }
}
