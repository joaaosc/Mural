import Foundation
import Testing

@testable import MuralKit

@Suite("Persistência isolada por mural")
struct BoardRepositoryTests {
    private func temporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MuralRepository-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func board(id: UUID, childOf folder: UUID? = nil, kind: ItemKind = .sticky, title: String = "Cartão") -> BoardItem {
        BoardItem(id: id, kind: kind, title: title, parentID: folder, position: BoardPoint(x: 17, y: 29))
    }

    @Test("Round trip preserva ordem, posições e parentID")
    func roundTripIsExact() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = BoardRepository(rootDirectory: root)
        let folderID = UUID()
        let firstID = UUID()
        let secondID = UUID()
        let expected = Board(items: [
            board(id: folderID, kind: .folder, title: "Pasta"),
            board(id: firstID, kind: .text, title: "Primeiro"),
            board(id: secondID, childOf: folderID, kind: .pdf, title: "PDF"),
        ])
        let id = BoardID()
        try await repository.save(id: id, board: expected, workspace: .default)
        let result = try #require(await repository.load(id))
        #expect(result.snapshot.board == expected)
        #expect(result.snapshot.board.items.map { $0.id } == expected.items.map { $0.id })
        #expect(result.snapshot.board.items.map { $0.parentID } == expected.items.map { $0.parentID })
    }

    @Test("A, B vazio e A novamente não mistura conteúdo")
    func boardsStayIndependent() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = BoardRepository(rootDirectory: root)
        let a = BoardID()
        let b = BoardID()
        let original = Board(items: [board(id: UUID(), kind: .text)])
        try await repository.save(id: a, board: original, workspace: .default)
        try await repository.save(id: b, board: Board(), workspace: .default)
        let loadedA = try #require(await repository.load(a))
        #expect(loadedA.snapshot.board == original)
        #expect(try await repository.load(b)?.snapshot.board == Board())
    }

    @Test("Cem ciclos A/B não acumulam drift")
    func repeatedSwitchesHaveNoDrift() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = BoardRepository(rootDirectory: root)
        let a = BoardID()
        let b = BoardID()
        let boardA = Board(items: [board(id: UUID(), kind: .image)])
        let boardB = Board(items: [board(id: UUID(), kind: .checklist)])
        for _ in 0..<100 {
            try await repository.save(id: a, board: boardA, workspace: .default)
            try await repository.save(id: b, board: boardB, workspace: .default)
        }
        #expect(try await repository.load(a)?.snapshot.board == boardA)
        #expect(try await repository.load(b)?.snapshot.board == boardB)
    }

    @Test("Workspace ausente usa defaults")
    func missingWorkspaceDefaults() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = BoardRepository(rootDirectory: root)
        let id = BoardID()
        try await repository.save(id: id, board: Board(), workspace: .default)
        try FileManager.default.removeItem(at: await repository.packageURL(for: id).appendingPathComponent("view-state.json"))
        let result = try #require(await repository.load(id))
        #expect(result.workspaceStatus == .missing)
        #expect(result.snapshot.workspace == BoardWorkspaceState(contentRevision: 0))
    }

    @Test("Workspace corrompido é preservado e relatado")
    func corruptedWorkspaceIsQuarantined() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = BoardRepository(rootDirectory: root)
        let id = BoardID()
        try await repository.save(id: id, board: Board(), workspace: .default)
        let viewState = await repository.packageURL(for: id).appendingPathComponent("view-state.json")
        try Data("not-json".utf8).write(to: viewState)
        let result = try #require(await repository.load(id))
        guard case .quarantined = result.workspaceStatus else {
            Issue.record("workspace não foi quarentenado: \(result.workspaceStatus)")
            return
        }
        #expect(result.snapshot.board == Board())
    }

    @Test("Path inválido é truncado no primeiro destino")
    func pathValidationTruncates() {
        let folderID = UUID()
        let childID = UUID()
        let rootID = UUID()
        let board = Board(items: [
            board(id: folderID, kind: .folder),
            board(id: childID, childOf: folderID, kind: .text),
            board(id: rootID, kind: .text),
        ])
        let state = BoardWorkspaceState(path: [
            .collection(BoardID(folderID)),
            .item(BoardID(rootID)),
            .item(BoardID(childID)),
        ])
        let result = state.canonicalized(for: board)
        #expect(result.state.path == [.collection(BoardID(folderID))])
        #expect(result.issues.contains(.invalidPath(index: 1)))
    }

    @Test("Zoom e posições não finitos não são persistidos")
    func invalidValuesAreCanonicalized() {
        let pdfID = UUID()
        let board = Board(items: [board(id: pdfID, kind: .pdf)])
        let state = BoardWorkspaceState(
            canvas: CanvasWorkspaceState(confirmedZoom: .infinity, logicalCenter: BoardPoint(x: .nan, y: 1)),
            readingPositions: [BoardID(pdfID): ReadingPosition(pdfID: BoardID(pdfID), page: 0, progress: .nan)]
        )
        let result = state.canonicalized(for: board)
        #expect(result.state.canvas.confirmedZoom == CanvasWorkspaceState.defaultZoom)
        #expect(result.state.canvas.isAtOrigin)
        #expect(result.state.readingPositions.isEmpty)
        #expect(result.issues.contains(.nonFiniteZoom))
        #expect(result.issues.contains(.nonFiniteCanvasCenter))

        let clamped = BoardWorkspaceState(canvas: CanvasWorkspaceState(confirmedZoom: 9))
            .canonicalized(for: board)
        #expect(clamped.state.canvas.confirmedZoom == CanvasWorkspaceState.zoomRange.upperBound)
        #expect(clamped.issues.contains(.zoomClamped))
    }

    @Test("Revisão atrasada não sobrescreve uma revisão nova")
    func staleRevisionIsRejected() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = BoardRepository(rootDirectory: root)
        let id = BoardID()
        try await repository.save(
            BoardRepositorySnapshot(
                manifest: BoardManifest(id: id, contentRevision: 2, workspaceRevision: 2),
                board: Board(items: [board(id: UUID())]), workspace: .default
            ))
        await #expect(throws: BoardRepositoryError.self) {
            try await repository.save(
                BoardRepositorySnapshot(
                    manifest: BoardManifest(id: id, contentRevision: 1, workspaceRevision: 1),
                    board: Board(), workspace: .default
                ))
        }
        #expect(try await repository.load(id)?.snapshot.board.items.count == 1)
    }
}
