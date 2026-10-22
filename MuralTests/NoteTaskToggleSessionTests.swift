import CoreGraphics
import Foundation
import MuralKit
import StretchText
import Testing

@testable import Mural

@Suite("Tarefas na nota, pela sessão")
@MainActor
struct NoteTaskToggleSessionTests {
    private static let body = "- [ ] Pintar a porta\n\nPrimeira frase. Segunda frase."
    private static let marked = "- [x] Pintar a porta\n\nPrimeira frase. Segunda frase."

    private func makeSession(directory: URL) async throws -> (BoardWindowSession, UUID) {
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Notas")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        try await makeReady(session)
        let model = try #require(session.model)
        let id = model.createNote().id
        model.updateNote(id, title: "Obra", text: Self.body)
        return (session, id)
    }

    private func makeReady(_ session: BoardWindowSession) async throws {
        await session.load()
        let metrics = CanvasScrollMetrics(
            contentOffset: .zero,
            containerSize: CGSize(width: 900, height: 700),
            contentSize: CGSize(width: 3_400, height: 2_800))
        session.restoreCanvas(boardID: session.boardID, generation: session.presentationGeneration, metrics: metrics)
        let target = session.zoom.scrollRequest?.point ?? .zero
        let reached = CanvasScrollMetrics(
            contentOffset: target,
            containerSize: metrics.containerSize,
            contentSize: metrics.contentSize,
            contentInsets: metrics.contentInsets)
        for _ in 0..<3 where session.restorationPhase != .ready {
            session.restoreCanvas(boardID: session.boardID, generation: session.presentationGeneration, metrics: reached)
        }
        #expect(session.restorationPhase == .ready)
    }

    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralNoteTask-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var open: Set<StretchID> { Set([StretchID(path: [1])].compactMap { $0 }) }

    @Test("Marcar pela sessão muda o texto da nota")
    func changesText() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (session, id) = try await makeSession(directory: directory)
        session.toggleNoteTask(id, segment: 0, source: Self.body)
        #expect(session.model?.item(id: id)?.text == Self.marked)
        await session.handleWindowWillClose()
    }

    @Test("Os parágrafos abertos passam a valer para o texto novo")
    func carriesOpenStretches() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (session, id) = try await makeSession(directory: directory)
        session.recordOpenStretches(open, for: id, source: Self.body)
        let before = session.openStretchIDs(for: id, source: Self.body)
        #expect(!before.isEmpty)
        session.toggleNoteTask(id, segment: 0, source: Self.body)
        #expect(session.openStretchIDs(for: id, source: Self.marked) == before)
        await session.handleWindowWillClose()
    }

    @Test("Memória de outro texto não é migrada")
    func ignoresOtherSource() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (session, id) = try await makeSession(directory: directory)
        session.recordOpenStretches(open, for: id, source: "Outro texto. Outra frase.")
        session.toggleNoteTask(id, segment: 0, source: Self.body)
        #expect(session.openStretchIDs(for: id, source: Self.marked).isEmpty)
        await session.handleWindowWillClose()
    }

    @Test("Com a sessão fechada, nada muda")
    func closedSession() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (session, id) = try await makeSession(directory: directory)
        await session.handleWindowWillClose()
        session.toggleNoteTask(id, segment: 0, source: Self.body)
        #expect(session.model?.item(id: id)?.text == Self.body)
    }
}
