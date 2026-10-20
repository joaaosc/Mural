import Foundation
import Testing

@testable import MuralKit

@Suite("Barreira da sessão do mural")
struct BoardSessionTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MuralSession-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func snapshot(id: BoardID = BoardID()) -> BoardRepositorySnapshot {
        BoardRepositorySnapshot(
            manifest: BoardManifest(id: id),
            board: Board(items: [BoardItem(kind: .text, title: "original")]),
            workspace: .default
        )
    }

    @Test("Mutação de conteúdo avança revisão e geração; flush idempotente não avança")
    func mutationsAdvanceMonotonically() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = snapshot()
        let session = BoardSession(snapshot: original, repository: BoardRepository(rootDirectory: directory))
        let generation = try await session.beginMutation(.content)
        try await session.update(
            board: Board(items: [BoardItem(kind: .text, title: "alterado")]),
            expectedGeneration: generation
        )
        #expect(await session.generation == 1)
        #expect(await session.manifest.contentRevision == 1)
        #expect(await session.isDirty)
        _ = try await session.flush()
        #expect(await session.isDirty == false)
        let revision = await session.manifest.contentRevision
        _ = try await session.flush()
        #expect(await session.manifest.contentRevision == revision)
    }

    @Test("Falha de flush mantém dirty e permite retry")
    func failedFlushCanRetry() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let initial = snapshot()
        let repository = BoardRepository(
            rootDirectory: directory,
            faultInjection: BoardRepositoryFaultInjection(points: [.afterSwap])
        )
        let session = BoardSession(snapshot: initial, repository: repository)
        try await session.update(board: Board(items: [BoardItem(kind: .text, title: "alterado")]))
        await #expect(throws: BoardRepositoryError.self) { _ = try await session.flush() }
        #expect(await session.isDirty)
        #expect(await session.isFlushInProgress == false)
        #expect(await session.lastFlushErrorDescription != nil)
        _ = try await session.flush()
        #expect(await session.isDirty == false)
    }

    @Test("Mutação durante flush é bloqueada pela barreira")
    func mutationDuringFlushIsBlocked() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = BoardRepositoryFaultGate()
        let repository = BoardRepository(
            rootDirectory: directory,
            faultInjection: BoardRepositoryFaultInjection(points: [.beforeSwap], gate: gate)
        )
        let session = BoardSession(snapshot: snapshot(), repository: repository)
        try await session.update(board: Board(items: [BoardItem(kind: .text, title: "alterado")]))
        let flushTask = Task { try await session.flush() }
        await gate.waitUntilReached()
        #expect(await session.isFlushInProgress)
        await #expect(throws: BoardSessionError.self) {
            try await session.update(board: Board(items: [BoardItem(kind: .text, title: "bloqueado")]))
        }
        await gate.release()
        await #expect(throws: BoardRepositoryError.self) { _ = try await flushTask.value }
        #expect(await session.isDirty)
    }

    @Test("Geração stale é rejeitada e não altera o snapshot")
    func staleGenerationIsRejected() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = BoardSession(snapshot: snapshot(), repository: BoardRepository(rootDirectory: directory))
        let generation = try await session.beginMutation(.content)
        try await session.update(board: Board(items: [BoardItem(kind: .text, title: "um")]))
        await #expect(throws: BoardSessionError.self) {
            try await session.update(
                board: Board(items: [BoardItem(kind: .text, title: "dois")]),
                expectedGeneration: generation
            )
        }
        #expect(await session.board.items.first?.title == "um")
    }
}
