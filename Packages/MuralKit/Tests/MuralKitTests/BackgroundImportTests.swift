import Foundation
import Testing
import UniformTypeIdentifiers

@testable import MuralKit

/// Importação em duas etapas: cópia fora do Main Actor e inserção no board depois.
@Suite("Importação fora do Main Actor")
@MainActor
struct BackgroundImportTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralBackgroundImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func source(in directory: URL, named name: String, bytes: Int = 4096) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(repeating: 1, count: bytes).write(to: url)
        return url
    }

    @Test("Preparar copia o arquivo sem mexer no board; confirmar insere o cartão")
    func prepareThenCommit() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("Board.mural", isDirectory: true)
        let model = BoardModel(board: Board(), store: BoardStore(directory: package), persistence: .deferred)
        let video = try source(in: root, named: "clipe.mov", bytes: 2 * 1024 * 1024)

        let prepared = await model.prepareFiles([video, root.appendingPathComponent("sumiu.png")])
        #expect(model.board.items.isEmpty)
        #expect(prepared.items.count == 1)
        #expect(prepared.failures == ["sumiu.png"])
        let preparedItem = try #require(prepared.items.first)
        let copied = try #require(model.fileURL(for: preparedItem))
        #expect(FileManager.default.fileExists(atPath: copied.path))

        let created = model.commit(prepared)
        #expect(created.count == 1)
        #expect(model.board.items.map(\.id) == created.map(\.id))
        #expect(model.lastError?.contains("sumiu.png") == true)
    }

    @Test("Pasta apagada durante a cópia: o conteúdo vai para o mural, nunca fica órfão")
    func commitFallsBackToRootWhenFolderVanished() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = BoardItem(kind: .folder, title: "Pasta")
        let model = BoardModel(
            board: Board(items: [folder]),
            store: BoardStore(directory: root.appendingPathComponent("Board.mural", isDirectory: true)),
            persistence: .deferred)
        let prepared = await model.prepareData(
            Data([1, 2, 3]), fileExtension: "png", kind: .image, title: "Imagem colada", parentID: folder.id)
        model.delete(folder.id)

        let created = try #require(model.commit(prepared, into: folder.id).first)
        #expect(created.parentID == nil)
        #expect(model.board.item(id: created.id)?.parentID == nil)
    }

    @Test("Descartar uma importação apaga os arquivos já copiados")
    func discardRemovesPreparedFiles() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = BoardModel(
            board: Board(), store: BoardStore(directory: root.appendingPathComponent("Board.mural", isDirectory: true)),
            persistence: .deferred)
        let prepared = await model.prepareData(
            Data([9, 9]), fileExtension: "pdf", kind: .pdf, title: "PDF colado")
        let preparedItem = try #require(prepared.items.first)
        let file = try #require(model.fileURL(for: preparedItem))
        #expect(FileManager.default.fileExists(atPath: file.path))

        model.discard(prepared)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(model.board.items.isEmpty)
    }

    @Test("Importação tipada não depende da extensão do arquivo temporário")
    func typedImportUsesUniformType() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = BoardModel(
            board: Board(), store: BoardStore(directory: root.appendingPathComponent("Board.mural", isDirectory: true)),
            persistence: .deferred)
        let source = try source(in: root, named: "provider-temporary-name", bytes: 16)
        let prepared = await model.prepareTypedFiles([
            BoardModel.TypedFile(url: source, contentTypeIdentifier: UTType.heic.identifier, title: "Foto")
        ])

        let item = try #require(prepared.items.first)
        #expect(item.kind == .image)
        #expect(item.title == "Foto")
        #expect(item.fileName?.hasSuffix(".heic") == true)
        #expect(model.commit(prepared).count == 1)
    }
}
