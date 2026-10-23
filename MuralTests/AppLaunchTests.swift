import AppKit
import MuralKit
import Testing

@testable import Mural

/// Sem nenhuma janela depois da restauração (ou ao clicar no Dock), o app abre a janela com a lista de murais; aberto pelo
/// início de sessão, ele fica só com o ícone da barra de menus, sem janela e fora do Dock. O Dock acompanha a janela.
@Suite("Abertura do app")
@MainActor
struct AppLaunchTests {
    /// Uma janela que se diz na tela sem aparecer: `MuralTabs.attach` só recusa uma segunda janela se a primeira está visível.
    private final class OnScreenWindow: NSWindow {
        override var isVisible: Bool { true }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    /// O evento de abertura do app, com ou sem a marca de início de sessão.
    private func openApplicationEvent(loginItem: Bool) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication), targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        if loginItem {
            event.setParam(
                NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
        }
        return event
    }

    private func launchNotification() -> Notification {
        Notification(name: NSApplication.didFinishLaunchingNotification)
    }

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

    @Test("Aberto pelo início de sessão, não abre a janela e tira o app do Dock")
    func loginItemLaunchOpensNoWindowAndLeavesTheDock() async throws {
        let opener = MainWindowOpener()
        var opened = 0
        opener.register { opened += 1 }
        var dock: [Bool] = []
        let delegate = MuralAppDelegate()
        delegate.windowOpener = opener
        delegate.hasOpenWindow = { false }
        delegate.launchWindowCheckDelay = .milliseconds(5)
        delegate.currentAppleEvent = { self.openApplicationEvent(loginItem: true) }
        delegate.dockPresence = { dock.append($0) }

        delegate.applicationDidFinishLaunching(launchNotification())
        // Bem além do atraso: uma verificação marcada por engano já teria aberto a janela.
        try await Task.sleep(for: .milliseconds(150))

        #expect(opened == 0)
        #expect(dock == [false])
    }

    @Test("Aberto pelo início de sessão com uma janela já restaurada, o Dock fica como está")
    func loginItemLaunchKeepsTheDockWhenAWindowWasRestored() async throws {
        var opened = 0
        let opener = MainWindowOpener()
        opener.register { opened += 1 }
        var dock: [Bool] = []
        let delegate = MuralAppDelegate()
        delegate.windowOpener = opener
        delegate.hasOpenWindow = { true }
        delegate.launchWindowCheckDelay = .milliseconds(5)
        delegate.currentAppleEvent = { self.openApplicationEvent(loginItem: true) }
        delegate.dockPresence = { dock.append($0) }

        delegate.applicationDidFinishLaunching(launchNotification())
        try await Task.sleep(for: .milliseconds(150))

        #expect(opened == 0)
        #expect(dock.isEmpty, "com janela, o app continua com Dock e menus")
    }

    @Test("Aberto de outro jeito, abre a janela depois do atraso e não mexe no Dock")
    func ordinaryLaunchOpensTheWindowAfterTheDelay() async {
        let opener = MainWindowOpener()
        var opened = 0
        opener.register { opened += 1 }
        var dock: [Bool] = []
        let delegate = MuralAppDelegate()
        delegate.windowOpener = opener
        delegate.hasOpenWindow = { false }
        delegate.launchWindowCheckDelay = .milliseconds(5)
        delegate.dockPresence = { dock.append($0) }

        for event in [nil, openApplicationEvent(loginItem: false)] {
            opened = 0
            delegate.currentAppleEvent = { event }
            delegate.applicationDidFinishLaunching(launchNotification())
            await waitUntil("a janela abrir depois do atraso") { opened == 1 }
        }

        #expect(dock.isEmpty, "a janela aberta é que traz o Dock de volta, por MuralTabs.attach")
    }

    @Test("Abrir a janela traz o Dock de volta; fechá-la o tira")
    func windowAttachAndDetachDriveTheDock() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AppLaunch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let tabs = MuralTabs(registry: BoardSessionRegistry(library: BoardLibrary(rootDirectory: directory)))
        var dock: [Bool] = []
        tabs.dockPresence = { dock.append($0) }

        let window = makeWindow()
        #expect(tabs.attach(window))
        #expect(dock == [true], "a janela apareceu: Dock e menus")

        tabs.detachWindow()
        #expect(dock == [true, false], "a janela fechou: só o ícone da barra de menus")
    }

    @Test("Uma segunda janela recusada não mexe no Dock")
    func refusedWindowLeavesTheDockAlone() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AppLaunch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let tabs = MuralTabs(registry: BoardSessionRegistry(library: BoardLibrary(rootDirectory: directory)))
        var dock: [Bool] = []
        tabs.dockPresence = { dock.append($0) }

        let first = OnScreenWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        first.isReleasedWhenClosed = false
        #expect(tabs.attach(first))
        #expect(!tabs.attach(makeWindow()), "já há uma janela na tela: a nova se fecha")
        #expect(dock == [true], "só a janela aceita traz o Dock")
    }

    @Test("Nos testes, o Dock do processo de teste não muda")
    func dockPresenceIsDisabledUnderTest() {
        #expect(!DockPresence.isEnabled)
    }
}
