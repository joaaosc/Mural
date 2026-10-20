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
            readingPositions: [pdfID: .pdf(itemID: pdfID, pageIndex: 0, scale: .nan, pointInPage: .zero)]
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

    @Test("Falha antes da troca preserva o pacote e remove staging")
    func faultBeforeSwapPreservesPackage() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = BoardID()
        let baseline = Board(items: [board(id: UUID(), title: "baseline")])
        let initial = BoardRepository(rootDirectory: root)
        try await initial.save(
            id: id,
            board: baseline,
            workspace: .default,
            manifest: BoardManifest(id: id, contentRevision: 1)
        )
        let failing = BoardRepository(
            rootDirectory: root,
            faultInjection: BoardRepositoryFaultInjection(points: [.beforeSwap])
        )
        await #expect(throws: BoardRepositoryError.self) {
            try await failing.save(
                id: id,
                board: Board(items: [board(id: UUID(), title: "novo")]),
                workspace: .default,
                manifest: BoardManifest(id: id, contentRevision: 2)
            )
        }
        #expect(try await initial.load(id)?.snapshot.board == baseline)
        try assertNoTransactionArtifacts(in: root)
    }

    @Test("Falha depois da troca restaura o pacote anterior")
    func faultAfterSwapRestoresPackage() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = BoardID()
        let baseline = Board(items: [board(id: UUID(), title: "baseline")])
        let initial = BoardRepository(rootDirectory: root)
        try await initial.save(
            id: id,
            board: baseline,
            workspace: .default,
            manifest: BoardManifest(id: id, contentRevision: 1)
        )
        let failing = BoardRepository(
            rootDirectory: root,
            faultInjection: BoardRepositoryFaultInjection(points: [.afterSwap])
        )
        await #expect(throws: BoardRepositoryError.self) {
            try await failing.save(
                id: id,
                board: Board(items: [board(id: UUID(), title: "novo")]),
                workspace: .default,
                manifest: BoardManifest(id: id, contentRevision: 2)
            )
        }
        #expect(try await initial.load(id)?.snapshot.board == baseline)
        try assertNoTransactionArtifacts(in: root)
    }

    @Test("Mesma revisão com conteúdo diferente é conflito, não overwrite")
    func equalRevisionConflictIsRejected() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = BoardRepository(rootDirectory: root)
        let id = BoardID()
        let baseline = Board(items: [board(id: UUID(), title: "primeiro")])
        try await repository.save(
            id: id,
            board: baseline,
            workspace: .default,
            manifest: BoardManifest(id: id, contentRevision: 4)
        )
        await #expect(throws: BoardRepositoryError.self) {
            try await repository.save(
                id: id,
                board: Board(items: [board(id: UUID(), title: "segundo")]),
                workspace: .default,
                manifest: BoardManifest(id: id, contentRevision: 4)
            )
        }
        #expect(try await repository.load(id)?.snapshot.board == baseline)
    }

    @Test("Schemas futuros não são restaurados como estado atual")
    func futureSchemasAreTyped() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = BoardID()
        let repository = BoardRepository(rootDirectory: root)
        try await repository.save(id: id, board: Board(), workspace: .default)

        let package = await repository.packageURL(for: id)
        let manifestURL = package.appendingPathComponent("manifest.json")
        var manifestObject = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
        manifestObject["schemaVersion"] = BoardManifest.currentSchemaVersion + 1
        try JSONSerialization.data(withJSONObject: manifestObject).write(to: manifestURL)
        await #expect(throws: BoardRepositoryError.self) { try await repository.load(id) }

        manifestObject["schemaVersion"] = BoardManifest.currentSchemaVersion
        try JSONSerialization.data(withJSONObject: manifestObject).write(to: manifestURL)
        let viewStateURL = package.appendingPathComponent("view-state.json")
        var workspaceObject = try JSONSerialization.jsonObject(with: Data(contentsOf: viewStateURL)) as! [String: Any]
        workspaceObject["schemaVersion"] = BoardWorkspaceState.currentSchemaVersion + 1
        try JSONSerialization.data(withJSONObject: workspaceObject).write(to: viewStateURL)
        let result = try #require(await repository.load(id))
        #expect(result.workspaceStatus == .futureSchema(version: BoardWorkspaceState.currentSchemaVersion + 1))
        #expect(result.snapshot.workspace == .default)
    }

    @Test("Reading positions usam IDs de item e payloads explícitos")
    func readingPositionsValidatePayloads() {
        let folderID = UUID()
        let itemID = UUID()
        let pdfID = UUID()
        let board = Board(items: [
            board(id: folderID, kind: .folder),
            board(id: itemID, childOf: folderID, kind: .text),
            board(id: pdfID, kind: .pdf),
        ])
        let state = BoardWorkspaceState(readingPositions: [
            folderID: .collection(folderID: folderID, firstVisibleItemID: itemID, relativeOffset: 0.25, fallbackContentY: 40),
            pdfID: .pdf(itemID: pdfID, pageIndex: 0, scale: 1.5, pointInPage: BoardPoint(x: 10, y: 20)),
            UUID(): .item(itemID: folderID, visibleContentY: .infinity),
        ])
        let result = state.canonicalized(for: board)
        #expect(result.state.readingPositions.count == 2)
        #expect(
            result.state.readingPositions[folderID]
                == .collection(folderID: folderID, firstVisibleItemID: itemID, relativeOffset: 0.25, fallbackContentY: 40))
        #expect(
            result.state.readingPositions[pdfID] == .pdf(itemID: pdfID, pageIndex: 0, scale: 1.5, pointInPage: BoardPoint(x: 10, y: 20)))
    }

    private func assertNoTransactionArtifacts(in root: URL) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(names.allSatisfy { !$0.contains(".mural-staging-") && !$0.contains(".mural-backup-") })
    }
}
