import AppKit

/// Abre a janela de Ajustes de fora de uma cena do SwiftUI: o painel da barra de menus é do AppKit e não lê o
/// `openSettings` do ambiente. `MuralCommands`, que existe mesmo sem janelas, registra aqui a ação do SwiftUI.
@MainActor
final class SettingsOpener {
    static let shared = SettingsOpener()

    private var action: (@MainActor () -> Void)?

    func register(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    /// Traz o Mural para a frente e abre os Ajustes. Sem ativar o app, a janela abriria atrás do app da frente: o painel
    /// de onde o pedido costuma vir não ativa o Mural.
    /// - Returns: `false` quando ainda não há ação registrada.
    @discardableResult
    func open() -> Bool {
        guard let action else { return false }
        NSApp.activate()
        action()
        return true
    }
}
