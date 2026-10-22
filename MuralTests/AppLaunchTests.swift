import AppKit
import Testing

@testable import Mural

/// O app nunca fica aberto só com a barra de menus: sem nenhuma janela depois da
/// restauração (ou ao clicar no Dock), abre a biblioteca.
@Suite("Abertura do app")
@MainActor
struct AppLaunchTests {
    @Test("Sem janela depois da abertura, abre a biblioteca; com janela, não faz nada")
    func opensLibraryOnlyWithoutWindows() {
        let opener = LibraryWindowOpener()
        var opened = 0
        opener.register { opened += 1 }
        let delegate = MuralAppDelegate()
        delegate.libraryOpener = opener

        delegate.hasOpenWindow = { true }
        delegate.openLibraryIfNoWindow()
        #expect(opened == 0)

        delegate.hasOpenWindow = { false }
        delegate.openLibraryIfNoWindow()
        #expect(opened == 1)
    }

    @Test("Clique no Dock sem janelas abre a biblioteca e dispensa o comportamento padrão")
    func reopenWithoutWindowsOpensLibrary() {
        let opener = LibraryWindowOpener()
        var opened = 0
        let delegate = MuralAppDelegate()
        delegate.libraryOpener = opener
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
