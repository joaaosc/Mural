import Foundation
import Testing

@testable import MuralKit

@Suite("Exclusão adiada")
@MainActor
struct DeferredDeletionTests {
    @Test("A mídia só é apagada quando a versão gravada já não tem o item")
    func deletionWaitsForPersistedBoard() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralDeferred-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = BoardModel(board: Board(), store: BoardStore(directory: directory), persistence: .deferred)
        let first = try #require(model.importData(Data([1]), fileExtension: "png", kind: .image, title: "A"))
        let second = try #require(model.importData(Data([2]), fileExtension: "png", kind: .image, title: "B"))
        let firstURL = try #require(model.fileURL(for: first))
        let secondURL = try #require(model.fileURL(for: second))

        model.delete(first.id)
        let persistedWithoutFirst = model.board
        // Excluído enquanto a gravação acima acontecia: ainda está na versão gravada.
        model.delete(second.id)

        model.finalizeDeferredDeletions(persistedBoard: persistedWithoutFirst)
        #expect(!FileManager.default.fileExists(atPath: firstURL.path))
        #expect(FileManager.default.fileExists(atPath: secondURL.path))

        model.finalizeDeferredDeletions(persistedBoard: model.board)
        #expect(!FileManager.default.fileExists(atPath: secondURL.path))
    }
}
