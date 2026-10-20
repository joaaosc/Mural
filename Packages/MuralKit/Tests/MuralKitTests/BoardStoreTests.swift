import Foundation
import Testing

@testable import MuralKit

@Suite("Gravação do mural")
struct BoardStoreTests {
    private func temporaryStore() throws -> BoardStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MuralKitTests-\(UUID().uuidString)")
        return BoardStore(directory: dir)
    }

    @Test("Sem arquivo, load devolve nil")
    func loadsNothing() throws {
        #expect(try temporaryStore().load() == nil)
    }

    @Test("Salvar e recarregar preserva o mural")
    func roundTrip() throws {
        let store = try temporaryStore()
        let board = SampleBoard.make(now: Date(timeIntervalSince1970: 1_000_000))
        try store.save(board)
        let loaded = try #require(try store.load())
        #expect(loaded == board)
        #expect(loaded.rootItems.count == board.rootItems.count)
        try? FileManager.default.removeItem(at: store.directory)
    }

    @Test("Arquivo corrompido lança erro específico")
    func corrupted() throws {
        let store = try temporaryStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("{ isto não é json".utf8).write(to: store.fileURL)
        #expect(throws: BoardStoreError.self) { try store.load() }
        try? FileManager.default.removeItem(at: store.directory)
    }

    @Test("Remover pasta remove os filhos")
    func removeFolder() {
        var board = SampleBoard.make()
        let folder = try! #require(board.rootItems.first { $0.kind == .folder && $0.title == "The Cottage" })
        #expect(!board.children(of: folder.id).isEmpty)
        board.remove(id: folder.id)
        #expect(board.item(id: folder.id) == nil)
        #expect(board.children(of: folder.id).isEmpty)
    }
}
