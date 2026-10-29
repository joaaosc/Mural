import AppKit
import Foundation
import MuralKit
import Testing

@testable import Mural

/// Sair do app espera as janelas de mural gravarem (⌘Q, logout, reinício).
@Suite("Término do app")
@MainActor
struct AppTerminationTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralTermination-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeReady(_ session: BoardWindowSession) async {
        await session.load()
        let metrics = CanvasScrollMetrics(
            contentOffset: .zero, containerSize: CGSize(width: 900, height: 700),
            contentSize: CGSize(width: 3_400, height: 2_800))
        for _ in 0..<3 where session.restorationPhase != .ready {
            session.restoreCanvas(boardID: session.boardID, generation: session.presentationGeneration, metrics: metrics)
        }
    }

    @Test("Sair grava as edições pendentes de todas as janelas abertas")
    func flushAllSavesEveryOpenWindow() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let registry = BoardSessionRegistry(library: library)
        let open = OpenBoardSessions()
        let routeA = try await library.createNamedBoard("A")
        let routeB = try await library.createNamedBoard("B")
        let a = BoardWindowSession(route: routeA, registry: registry, openSessions: open)
        let b = BoardWindowSession(route: routeB, registry: registry, openSessions: open)
        await makeReady(a)
        await makeReady(b)
        #expect(open.live.count == 2)

        // Editado logo antes do ⌘Q: o debounce de 250 ms ainda não disparou.
        _ = a.model?.importText("pendente em A")
        a.captureBoardIfNeeded()
        _ = b.model?.importText("pendente em B")
        b.captureBoardIfNeeded()

        let unsaved = await open.flushAll(timeout: .seconds(5))
        #expect(unsaved.isEmpty)
        #expect(try #require(try await library.open(routeA)).board.items.contains { $0.title.contains("em A") })
        #expect(try #require(try await library.open(routeB)).board.items.contains { $0.title.contains("em B") })
    }

    @Test("Uma gravação que falha é relatada pelo título do mural")
    func flushAllReportsFailures() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let route = try await BoardLibrary(rootDirectory: directory).createNamedBoard("Falha")
        let failing = BoardLibrary(
            rootDirectory: directory, repositoryFaultInjection: BoardRepositoryFaultInjection(points: [.beforeSwap]))
        let open = OpenBoardSessions()
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: failing), openSessions: open)
        await makeReady(session)
        _ = session.model?.importText("não vai gravar")
        session.captureBoardIfNeeded()

        #expect(await open.flushAll(timeout: .seconds(5)) == ["Falha"])
    }

    @Test("Uma gravação presa não segura o término além do prazo")
    func flushAllHonoursTimeout() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let route = try await BoardLibrary(rootDirectory: directory).createNamedBoard("Presa")
        let gate = BoardRepositoryFaultGate()
        let stuck = BoardLibrary(
            rootDirectory: directory,
            repositoryFaultInjection: BoardRepositoryFaultInjection(points: [.beforeSwap], gate: gate))
        let open = OpenBoardSessions()
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: stuck), openSessions: open)
        await makeReady(session)
        _ = session.model?.importText("presa")
        session.captureBoardIfNeeded()

        let clock = ContinuousClock()
        var unsaved: [String] = []
        let elapsed = await clock.measure {
            unsaved = await open.flushAll(timeout: .milliseconds(200))
        }
        #expect(unsaved == ["Presa"])
        #expect(elapsed < .seconds(2))
        await gate.release()
    }

    @Test("O delegate termina na hora sem janelas e depois de gravar com janelas")
    func delegateRepliesAfterFlushing() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Delegate")
        let open = OpenBoardSessions()
        let delegate = MuralAppDelegate()
        delegate.openSessions = open
        var replies: [Bool] = []
        delegate.reply = { replies.append($0) }
        delegate.confirmQuitWithUnsavedBoards = { _ in
            Issue.record("não deveria perguntar: tudo foi salvo")
            return false
        }
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateNow)

        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library), openSessions: open)
        await makeReady(session)
        _ = session.model?.importText("salvo ao sair")
        session.captureBoardIfNeeded()
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        for _ in 0..<100 where replies.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(replies == [true])
        #expect(try #require(try await library.open(route)).board.items.contains { $0.title.contains("salvo ao sair") })
    }

    @Test("Rascunhos recusados sobrevivem ao fechamento e impedem saída silenciosa")
    func closedSessionsRetainDraftsAndWarnOnQuit() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let registry = BoardSessionRegistry(library: library)
        let open = OpenBoardSessions()
        for name in ["Primeiro", "Segundo"] {
            let route = try await library.createNamedBoard(name)
            let session = BoardWindowSession(route: route, registry: registry, openSessions: open)
            await makeReady(session)
            let model = try #require(session.model)
            let note = try #require(model.importText("Original", as: .text))
            session.setNoteDraft(NoteDraft(title: name, text: "Texto de \(name)"), for: note.id)
            model.isReadOnly = true
            await session.handleWindowWillClose()
        }
        #expect(open.live.isEmpty)
        #expect(open.retainedDrafts.count == 2)
        #expect(open.unwrittenDraftText?.contains("Texto de Primeiro") == true)
        #expect(open.unwrittenDraftText?.contains("Texto de Segundo") == true)

        let delegate = MuralAppDelegate()
        delegate.openSessions = open
        var replies: [Bool] = []
        delegate.reply = { replies.append($0) }
        delegate.confirmQuitWithDrafts = { text in
            #expect(text?.contains("Texto de Primeiro") == true)
            return false
        }
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        for _ in 0..<100 where replies.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(replies == [false])
        #expect(open.retainedDrafts.count == 2)
        open.discardRetainedDrafts(open.closedDraftSnapshot)
        #expect(open.retainedDrafts.isEmpty)
    }

    @Test("Sair de mural aberto em somente leitura identifica o rascunho recusado")
    func openReadOnlyDraftIsNotReportedAsSaved() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Compartilhado")
        let open = OpenBoardSessions()
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library), openSessions: open)
        await makeReady(session)
        let model = try #require(session.model)
        let note = try #require(model.importText("Original", as: .text))
        session.setNoteDraft(NoteDraft(text: "Edição local"), for: note.id)
        model.isReadOnly = true
        #expect(await open.flushAll(timeout: .seconds(5)) == ["Compartilhado"])
        #expect(open.unwrittenDraftText?.contains("Edição local") == true)
        await session.handleWindowWillClose()
        open.discardRetainedDrafts(open.closedDraftSnapshot)
    }
    @Test("Sair confirma novamente quando o rascunho muda durante o aviso")
    func quitRechecksDraftAfterConfirmation() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Mural")
        let open = OpenBoardSessions()
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library), openSessions: open)
        await makeReady(session)
        let model = try #require(session.model)
        let note = try #require(model.importText("Original", as: .text))
        session.setNoteDraft(NoteDraft(text: "Primeiro"), for: note.id)
        model.isReadOnly = true
        let delegate = MuralAppDelegate()
        delegate.openSessions = open
        var replies: [Bool] = []
        var warnings = 0
        delegate.reply = { replies.append($0) }
        delegate.confirmQuitWithDrafts = { _ in
            warnings += 1
            if warnings == 1 { session.setNoteDraft(NoteDraft(text: "Mudou"), for: note.id) }
            return warnings == 1
        }
        delegate.confirmQuitWithUnsavedBoards = { _ in true }
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        for _ in 0..<100 where replies.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(warnings == 2)
        #expect(replies == [false])
    }

    @Test("Descarte não remove rascunho alterado depois da confirmação")
    func discardRechecksDraft() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Mural")
        let open = OpenBoardSessions()
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library), openSessions: open)
        await makeReady(session)
        let model = try #require(session.model)
        let note = try #require(model.importText("Original", as: .text))
        session.setNoteDraft(NoteDraft(text: "Primeiro"), for: note.id)
        model.isReadOnly = true
        await session.handleWindowWillClose()
        let snapshot = open.closedDraftSnapshot
        session.setNoteDraft(NoteDraft(text: "Mudou"), for: note.id)
        open.discardRetainedDrafts(snapshot)
        #expect(open.retainedDrafts.count == 1)
    }

}
