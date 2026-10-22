import AppKit
import Foundation
import MuralKit
import Testing

@testable import Mural

@Suite("Lifecycle da janela de mural")
@MainActor
struct WindowLifecycleTests {
    @Test("O observer filtra a janela exata e remove o token no teardown")
    func observerFiltersWindowAndDismantles() async {
        let firstWindow = makeWindow()
        let secondWindow = makeWindow()
        firstWindow.contentView = NSView(frame: .zero)
        secondWindow.contentView = NSView(frame: .zero)

        let observer = WindowLifecycleObserverView(frame: .zero)
        var callbackCount = 0
        observer.onWillClose = { callbackCount += 1 }
        firstWindow.contentView?.addSubview(observer)
        observer.updateWindowObservation()

        postWillClose(for: secondWindow)
        await settleCallback()
        #expect(callbackCount == 0)

        postWillClose(for: firstWindow)
        await settleCallback()
        #expect(callbackCount == 1)

        observer.removeFromSuperview()
        secondWindow.contentView?.addSubview(observer)
        observer.updateWindowObservation()

        postWillClose(for: firstWindow)
        await settleCallback()
        #expect(callbackCount == 1)

        postWillClose(for: secondWindow)
        await settleCallback()
        #expect(callbackCount == 2)

        WindowLifecycleObserver.dismantleNSView(observer, coordinator: ())
        postWillClose(for: secondWindow)
        await settleCallback()
        #expect(callbackCount == 2)
    }

    @Test("Fechamento bem-sucedido aposenta a sessão e reabrir carrega outra adaptação")
    func successfulCloseRetiresRegistrySession() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Fechamento")
        let registry = BoardSessionRegistry(library: library)
        let session = BoardWindowSession(route: route, registry: registry)
        await session.load()
        let item = try #require(session.model?.importText("persistir no fechamento"))
        session.captureBoardIfNeeded()

        await session.handleWindowWillClose()
        let retiredDomainSession = await registry.session(for: session.boardID)
        #expect(retiredDomainSession == nil)

        let reopened = BoardWindowSession(route: route, registry: registry)
        await reopened.load()
        #expect(reopened !== session)
        #expect(reopened.model?.item(id: item.id)?.text == "persistir no fechamento")
    }

    @Test("Falha de flush mantém sessão dirty no registry e a reabertura reutiliza-a")
    func failedCloseKeepsDirtyRegistrySession() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let initialLibrary = BoardLibrary(rootDirectory: directory)
        let route = try await initialLibrary.createNamedBoard("Flush falho")
        let failingLibrary = BoardLibrary(
            rootDirectory: directory,
            repositoryFaultInjection: BoardRepositoryFaultInjection(points: [.beforeSwap]))
        let registry = BoardSessionRegistry(library: failingLibrary)
        let session = BoardWindowSession(route: route, registry: registry)
        await session.load()
        let item = try #require(session.model?.importText("recuperável"))
        session.captureBoardIfNeeded()
        let domainSession = try #require(await registry.session(for: session.boardID))

        await session.handleWindowWillClose()
        #expect(session.isDirty)

        // A second notification must not retry or retire the same session.
        await session.handleWindowWillClose()
        #expect(session.isDirty)
        let reopenedDomainSession = try #require(await registry.session(for: session.boardID))
        #expect(reopenedDomainSession === domainSession)
        #expect(await reopenedDomainSession.isDirty)

        let reopened = BoardWindowSession(route: route, registry: registry)
        await reopened.load()
        #expect(reopened.model?.item(id: item.id)?.text == "recuperável")
    }

    @Test("A rota de biblioteca não participa do retirement de janela")
    func libraryRouteDoesNotRetire() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let registry = BoardSessionRegistry(library: library)
        let session = BoardWindowSession(route: .library, registry: registry)
        let originalEpoch = session.presentationEpoch

        await session.handleWindowWillClose()

        #expect(session.presentationEpoch == originalEpoch)
        #expect(await registry.session(for: session.boardID) == nil)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralWindowLifecycle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [],
            backing: .buffered,
            defer: true)
    }

    private func postWillClose(for window: NSWindow) {
        NotificationCenter.default.post(
            name: NSWindow.willCloseNotification,
            object: window)
    }

    private func settleCallback() async {
        await Task.yield()
        await Task.yield()
    }
}
