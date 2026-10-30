import Foundation
import StretchText
import Testing

@testable import MuralKit

@Suite("Ida e volta da persistência do mural")
struct PersistenceRoundTripTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MuralRoundTrip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func savedID(_ route: BoardRoute) -> BoardID? {
        if case .saved(let id) = route { return id }
        return nil
    }

    /// Mural com todos os campos de posição e tamanho preenchidos, mais o estado de navegação.
    private struct Fixture {
        static let noteText = "Primeira frase. Segunda frase.\n\nOutro bloco. Com duas frases."

        let folderID = UUID()
        let insideStickyID = UUID()
        let looseStickyID = UUID()
        let imageID = UUID()
        let noteID = UUID()
        let imageFileName = "foto.png"
        let imageData: Data

        /// Calculados uma vez: `Date.now` e UUIDs novos tornariam duas leituras diferentes.
        let board: Board
        let workspace: BoardWorkspaceState

        init() throws {
            imageData = try TestImages.png(width: 8, height: 8)
            board = Self.makeBoard(
                folderID: folderID, insideStickyID: insideStickyID, looseStickyID: looseStickyID, imageID: imageID,
                noteID: noteID, imageFileName: imageFileName)
            workspace = Self.makeWorkspace(folderID: folderID, noteID: noteID)
        }

        private static func makeBoard(
            folderID: UUID, insideStickyID: UUID, looseStickyID: UUID, imageID: UUID, noteID: UUID, imageFileName: String
        ) -> Board {
            Board(
                items: [
                    BoardItem(id: folderID, kind: .folder, title: "Pasta", position: BoardPoint(x: 40, y: 60)),
                    BoardItem(
                        id: insideStickyID, kind: .sticky, title: "Dentro", parentID: folderID,
                        position: BoardPoint(x: 5, y: 6), text: "Dentro", folderPosition: BoardPoint(x: 77, y: 88)),
                    BoardItem(
                        id: looseStickyID, kind: .sticky, title: "Solto", position: BoardPoint(x: 123, y: 456),
                        text: "Solto", size: BoardSize(width: 210, height: 180)),
                    BoardItem(
                        id: imageID, kind: .image, title: "Foto", position: BoardPoint(x: 700, y: 20),
                        fileName: imageFileName, size: BoardSize(width: 320, height: 240)),
                    BoardItem(id: noteID, kind: .text, title: "Nota", position: BoardPoint(x: 10, y: 900), text: Self.noteText),
                ],
                freeTexts: [
                    BoardFreeText(text: "Primeiro texto", position: BoardPoint(x: 250, y: 310), size: BoardSize(width: 200, height: 90)),
                    BoardFreeText(text: "Segundo texto", position: BoardPoint(x: -30, y: 15.5), size: BoardSize(width: 150, height: 60)),
                ])
        }

        private static func makeWorkspace(folderID: UUID, noteID: UUID) -> BoardWorkspaceState {
            BoardWorkspaceState(
                contentRevision: 1,
                canvas: CanvasWorkspaceState(confirmedZoom: 1.7, logicalCenter: BoardPoint(x: 300, y: 200)),
                path: [.collection(folderID)],
                readingPositions: [noteID: .item(itemID: noteID, visibleContentY: 120)],
                openStretches: [
                    noteID: OpenStretchMemory(source: Self.noteText, openIDs: [[0], [1]].compactMap { StretchID(path: $0) })
                ])
        }
    }

    /// Compara campo a campo, item por item, para que a falha aponte o campo que mudou.
    private func expectSame(_ loaded: BoardRepositorySnapshot, _ fixture: Fixture) {
        let board = fixture.board
        #expect(loaded.board.items.map(\.id) == board.items.map(\.id))
        for original in board.items {
            guard let item = loaded.board.item(id: original.id) else {
                Issue.record("cartão \(original.id) ausente")
                continue
            }
            #expect(item.kind == original.kind)
            #expect(item.parentID == original.parentID)
            #expect(item.position == original.position)
            #expect(item.folderPosition == original.folderPosition)
            #expect(item.size == original.size)
            #expect(item.fileName == original.fileName)
            #expect(item.text == original.text)
        }
        #expect(loaded.board.freeTexts.count == board.freeTexts.count)
        for (original, freeText) in zip(board.freeTexts, loaded.board.freeTexts) {
            #expect(freeText.text == original.text)
            #expect(freeText.position == original.position)
            #expect(freeText.size == original.size)
        }
        let expected = fixture.workspace
        #expect(loaded.workspace.canvas.confirmedZoom == expected.canvas.confirmedZoom)
        #expect(loaded.workspace.canvas.logicalCenter == expected.canvas.logicalCenter)
        #expect(loaded.workspace.path == expected.path)
        #expect(loaded.workspace.readingPositions == expected.readingPositions)
        #expect(loaded.workspace.openStretches == expected.openStretches)
    }

    @Test("Salvar e reabrir pelo repositório preserva posições, tamanhos e navegação")
    func repositoryRoundTrip() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try Fixture()
        let repository = BoardRepository(rootDirectory: root)
        let id = BoardID()
        let snapshot = BoardRepositorySnapshot(
            manifest: BoardManifest(id: id, name: "Ida e volta", contentRevision: 1),
            board: fixture.board, workspace: fixture.workspace)
        try await repository.save(snapshot)
        let items = await repository.packageURL(for: id).appendingPathComponent("Items", isDirectory: true)
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        try fixture.imageData.write(to: items.appendingPathComponent(fixture.imageFileName))

        // Reabre com um repositório novo, sem cache em memória.
        let reopened = BoardRepository(rootDirectory: root)
        let loaded = try #require(await reopened.load(id))
        expectSame(loaded.snapshot, fixture)
        #expect(loaded.snapshot.board == fixture.board)
        #expect(loaded.snapshot.workspace == fixture.workspace)
        #expect(loaded.snapshot.manifest.contentRevision == 1)
        #expect(loaded.snapshot.workspace.contentRevision == loaded.snapshot.manifest.contentRevision)
    }

    @Test("Exportar e importar pela biblioteca preserva posições, tamanhos e navegação")
    func libraryExportImportRoundTrip() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try Fixture()
        let library = BoardLibrary(rootDirectory: root)
        let route = try await library.createNamedBoard("Original")
        let id = try #require(savedID(route))
        let repository = try await library.repository(for: route)
        try await repository.save(
            BoardRepositorySnapshot(
                manifest: BoardManifest(id: id, name: "Original", contentRevision: 1),
                board: fixture.board, workspace: fixture.workspace))
        let items = await repository.packageURL(for: id).appendingPathComponent("Items", isDirectory: true)
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        try fixture.imageData.write(to: items.appendingPathComponent(fixture.imageFileName))

        let exported = try await library.exportPackage(route)
        let imported = try await library.importPackage(from: exported)
        try await library.cleanupTransfer(exported)

        #expect(imported != route)
        let importedID = try #require(savedID(imported))
        #expect(importedID != id)
        let loaded = try #require(await library.open(imported))
        expectSame(loaded, fixture)
        #expect(loaded.board == fixture.board)
        #expect(loaded.workspace.contentRevision == loaded.manifest.contentRevision)

        // O arquivo da imagem acompanha o pacote importado.
        let importedRepository = try await library.repository(for: imported)
        let file = await importedRepository.packageURL(for: importedID)
            .appendingPathComponent("Items", isDirectory: true).appendingPathComponent(fixture.imageFileName)
        #expect(try Data(contentsOf: file) == fixture.imageData)
    }
}
