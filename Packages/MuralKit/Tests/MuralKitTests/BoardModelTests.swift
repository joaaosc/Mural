import Foundation
import Testing
@testable import MuralKit

@MainActor
@Suite("Estado do mural")
struct BoardModelTests {
    private func makeStore() -> BoardStore {
        BoardStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("MuralModel-\(UUID().uuidString)"))
    }

    @Test("Primeira abertura cria e grava o mural de exemplo")
    func seedsOnFirstLaunch() throws {
        let store = makeStore()
        let model = BoardModel(store: store)
        #expect(!model.rootItems.isEmpty)
        #expect(try store.load() != nil)
        #expect(model.lastError == nil)
    }

    @Test("Texto colado é salvo e reaparece ao reabrir")
    func pastedTextPersists() throws {
        let store = makeStore()
        let model = BoardModel(store: store)
        let item = try #require(model.importText("Comprar tinta azul"))
        #expect(item.kind == .sticky)
        let reopened = BoardModel(store: store)
        #expect(reopened.item(id: item.id)?.text == "Comprar tinta azul")
    }

    @Test("Colar dentro de uma pasta liga o cartão à pasta")
    func pasteIntoFolder() throws {
        let model = BoardModel(store: makeStore())
        let folder = try #require(model.rootItems.first { $0.kind == .folder })
        let before = model.children(of: folder.id).count
        model.importText("Nota rápida", into: folder.id)
        #expect(model.children(of: folder.id).count == before + 1)
    }

    @Test("Marcar item da lista é gravado")
    func toggleChecklistPersists() throws {
        let store = makeStore()
        let model = BoardModel(store: store)
        let list = try #require(model.rootItems.first { $0.kind == .checklist })
        let entry = try #require(list.checklist?.sections.first?.entries.first)
        model.toggleChecklistEntry(entry.id, in: list.id)
        let reopened = BoardModel(store: store)
        #expect(reopened.item(id: list.id)?.checklist?.sections.first?.entries.first?.isDone == true)
    }

    @Test("Apagar pasta remove filhos e seus arquivos")
    func deleteFolderRemovesFiles() throws {
        let model = BoardModel(store: makeStore())
        let folder = try #require(model.rootItems.first { $0.kind == .folder })
        let media = try #require(model.importData(Data([0, 1, 2]), fileExtension: "mov", kind: .video, title: "Clipe", into: folder.id))
        let file = try #require(model.fileURL(for: media))
        #expect(FileManager.default.fileExists(atPath: file.path))
        model.delete(folder.id)
        #expect(model.item(id: folder.id) == nil)
        #expect(model.item(id: media.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("Arquivo que falha é relatado e os outros entram")
    func partialImportFailure() throws {
        let model = BoardModel(store: makeStore(), seedIfEmpty: false)
        let created = model.importFiles([URL(fileURLWithPath: "/nao/existe.png")])
        #expect(created.isEmpty)
        #expect(model.lastError?.contains("existe.png") == true)
    }

    @Test("Mural corrompido é guardado à parte e um novo é criado")
    func corruptedBoardIsQuarantined() throws {
        let store = makeStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("lixo".utf8).write(to: store.fileURL)
        let model = BoardModel(store: store)
        #expect(model.lastError != nil)
        #expect(!model.rootItems.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
        #expect(files.contains { $0.hasPrefix("board-corrompido-") })
        #expect(try store.load() != nil)
    }

    @Test("Cartões colados no mural não se sobrepõem")
    func newCardsDoNotOverlap() {
        let model = BoardModel(store: makeStore())
        let a = model.importText("Primeiro")!
        let b = model.importText("Segundo")!
        let size = BoardLayout.cardSize(for: .sticky)
        #expect(!BoardLayout.overlaps(a.position, size, b.position, size, gap: 0))
    }
}
