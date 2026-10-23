import AppKit
import Foundation

/// O Dock e a barra de menus do Mural acompanham a janela do mural.
///
/// Com janela, o app é comum (`.regular`: Dock e barra de menus). Sem janela, fica só com o ícone da barra de menus
/// (`.accessory`: fora do Dock e sem barra de menus). A política muda enquanto o app roda, e não é fixada por `LSUIElement`:
/// a janela do mural precisa dos menus (⌘N, ⌘W, Visualizar) e `.accessory` não tem barra de menus, então o app não pode
/// ficar sempre fora do Dock.
@MainActor
enum DockPresence {
    /// Falso nos testes (de interface ou do app): trocar a política de ativação do processo de teste o tiraria do Dock e da
    /// frente de quem roda os testes.
    static var isEnabled: Bool {
        !LaunchConfiguration.isUITesting && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    /// Uma janela de mural apareceu: o Dock e os menus voltam, e o app vem para a frente.
    static func windowDidAppear() {
        guard isEnabled else { return }
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate()
    }

    /// Não há janela de mural: o app sai do Dock e fica só com o ícone da barra de menus.
    static func noWindow() {
        guard isEnabled else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Como o app foi aberto.
enum LaunchContext {
    /// O app foi aberto pelo início de sessão?
    ///
    /// O sistema marca o evento de abertura (`kAEOpenApplication`) com o parâmetro `keyAEPropData` valendo
    /// `keyAELaunchedAsLogInItem`. Qualquer outro evento, ou a falta dele, é uma abertura comum (Finder, Spotlight, Dock).
    nonisolated static func isLoginItemLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event,
            event.eventClass == AEEventClass(kCoreEventClass),
            event.eventID == AEEventID(kAEOpenApplication)
        else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
}
