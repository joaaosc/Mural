import AppKit
import Testing

@testable import Mural

/// O app nunca fica aberto só com a barra de menus: sem nenhuma janela depois da
/// restauração (ou ao clicar no Dock), abre a janela com a lista de murais.
@Suite("Abertura do app")
@MainActor
struct AppLaunchTests {
    @Test("Sem janela depois da abertura, abre a janela; com janela, não faz nada")
    func opensWindowOnlyWithoutWindows() {
        let opener = MainWindowOpener()
        var opened = 0
        opener.register { opened += 1 }
        let delegate = MuralAppDelegate()
        delegate.windowOpener = opener

        delegate.hasOpenWindow = { true }
        delegate.openWindowIfNeeded()
        #expect(opened == 0)

        delegate.hasOpenWindow = { false }
        delegate.openWindowIfNeeded()
        #expect(opened == 1)
    }

    @Test("Clique no Dock sem janelas abre a janela e dispensa o comportamento padrão")
    func reopenWithoutWindowsOpensWindow() {
        let opener = MainWindowOpener()
        var opened = 0
        let delegate = MuralAppDelegate()
        delegate.windowOpener = opener
        delegate.hasOpenWindow = { false }

        // Sem ação registrada, deixa o AppKit seguir o padrão.
        #expect(delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false))
        opener.register { opened += 1 }
        #expect(!delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false))
        #expect(opened == 1)
        #expect(delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: true))
        #expect(opened == 1)
    }
}
