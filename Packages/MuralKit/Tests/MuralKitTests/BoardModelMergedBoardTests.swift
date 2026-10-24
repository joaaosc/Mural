import Foundation
import Testing

@testable import MuralKit

@Suite("Mural trocado pelo resultado de uma junção")
@MainActor
struct BoardModelMergedBoardTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralMergedBoard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Dois cartões de imagem, cada um com o seu arquivo em `Items/`.
    private struct Scene {
        let model: BoardModel
        let store: BoardStore
        let first: BoardItem
        let second: BoardItem
        let firstURL: URL
        let secondURL: URL
    }

    private func scene(in directory: URL, persistence: BoardModel.Persistence) throws -> Scene {
        let store = BoardStore(directory: directory)
        let model = BoardModel(board: Board(), store: store, persistence: persistence)
        let first = try #require(model.importData(Data([1]), fileExtension: "png", kind: .image, title: "A"))
        let second = try #require(model.importData(Data([2]), fileExtension: "png", kind: .image, title: "B"))
        return Scene(
            model: model, store: store, first: first, second: second,
            firstURL: try #require(model.fileURL(for: first)), secondURL: try #require(model.fileURL(for: second)))
    }

    @Test("A junção entra no mural, e a mídia que ele deixou de citar só sai depois da gravação")
    func releasedFilesWaitForTheSavedBoard() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let scene = try scene(in: directory, persistence: .deferred)
        let before = scene.model.board
        var merged = before
        _ = merged.remove(id: scene.first.id)

        #expect(scene.model.applyMergedBoard(merged))
        #expect(scene.model.board == merged)
        #expect(FileManager.default.fileExists(atPath: scene.firstURL.path), "nada é apagado antes da gravação")

        // A versão gravada ainda cita o arquivo: ele continua na fila.
        scene.model.finalizeDeferredDeletions(persistedBoard: before)
        #expect(FileManager.default.fileExists(atPath: scene.firstURL.path))

        scene.model.finalizeDeferredDeletions(persistedBoard: merged)
        #expect(!FileManager.default.fileExists(atPath: scene.firstURL.path))
        #expect(FileManager.default.fileExists(atPath: scene.secondURL.path), "quem o mural ainda cita fica")
    }

    @Test("Um arquivo que a junção seguinte volta a citar sai da fila sem ser apagado")
    func fileCitedAgainIsKept() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let scene = try scene(in: directory, persistence: .deferred)
        let before = scene.model.board
        var without = before
        _ = without.remove(id: scene.first.id)

        scene.model.applyMergedBoard(without)
        scene.model.applyMergedBoard(before)
        scene.model.finalizeDeferredDeletions(persistedBoard: before)
        #expect(FileManager.default.fileExists(atPath: scene.firstURL.path))
    }

    @Test("Vale também num mural só para ver, sem recusa nem aviso")
    func worksInReadOnly() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let scene = try scene(in: directory, persistence: .deferred)
        scene.model.isReadOnly = true
        scene.model.lastError = nil
        var merged = scene.model.board
        merged.add(BoardItem(kind: .text, title: "Chegou", position: BoardPoint(x: 10, y: 10), text: "de outra pessoa"))

        #expect(scene.model.applyMergedBoard(merged))
        #expect(scene.model.board == merged)
        #expect(scene.model.lastError == nil)
    }

    @Test("Um mural igual ao de agora não muda nada")
    func identicalBoardIsANoOp() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let scene = try scene(in: directory, persistence: .deferred)
        let before = scene.model.board

        #expect(scene.model.applyMergedBoard(before))
        #expect(scene.model.board == before)
        scene.model.finalizeDeferredDeletions(persistedBoard: before)
        #expect(FileManager.default.fileExists(atPath: scene.firstURL.path))
        #expect(FileManager.default.fileExists(atPath: scene.secondURL.path))
    }

    @Test("Na gravação imediata o mural é gravado primeiro e só então os arquivos saem")
    func immediateModeSavesBeforeRemovingFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let scene = try scene(in: directory, persistence: .immediate)
        var merged = scene.model.board
        _ = merged.remove(id: scene.first.id)

        #expect(scene.model.applyMergedBoard(merged))
        #expect(scene.model.board == merged)
        // O disco guarda as datas em segundos inteiros: compara os cartões, não o mural byte a byte.
        #expect(try scene.store.load()?.items.map(\.id) == merged.items.map(\.id))
        #expect(!FileManager.default.fileExists(atPath: scene.firstURL.path))
        #expect(FileManager.default.fileExists(atPath: scene.secondURL.path))
    }

    @Test("Se a gravação imediata falha, o mural e os arquivos ficam como estavam e o aviso explica")
    func immediateModeFailureChangesNothing() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let scene = try scene(in: directory, persistence: .immediate)
        let before = scene.model.board
        var merged = before
        _ = merged.remove(id: scene.first.id)
        // Uma pasta no lugar do `board.json` faz a gravação atômica falhar.
        try FileManager.default.removeItem(at: scene.store.fileURL)
        try FileManager.default.createDirectory(at: scene.store.fileURL, withIntermediateDirectories: true)
        try Data([1]).write(to: scene.store.fileURL.appendingPathComponent("trava"))

        #expect(!scene.model.applyMergedBoard(merged))
        #expect(scene.model.board == before)
        #expect(scene.model.lastError?.contains("Nenhum arquivo foi removido.") == true)
        #expect(FileManager.default.fileExists(atPath: scene.firstURL.path))
    }
}
