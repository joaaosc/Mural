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
        let reopened = BoardModel(store: model.store)
        #expect(reopened.item(id: folder.id) == nil)
        #expect(reopened.item(id: media.id) == nil)
    }

    @Test("Falha ao salvar a exclusão preserva mural e arquivos")
    func deleteSaveFailurePreservesBoardAndFiles() throws {
        let store = makeStore()
        let model = BoardModel(store: store)
        let media = try #require(model.importData(Data([3, 4, 5]), fileExtension: "mov", kind: .video, title: "Clipe"))
        let file = try #require(model.fileURL(for: media))
        let boardBeforeDelete = model.board

        // Faz o destino do JSON ser uma pasta: a leitura inicial continua válida,
        // mas a próxima gravação falha sem depender de permissões do sistema.
        try FileManager.default.removeItem(at: store.fileURL)
        try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: true)

        model.delete(media.id)

        #expect(model.board == boardBeforeDelete)
        #expect(model.item(id: media.id) != nil)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(model.lastError != nil)
    }

    @Test("Persistência suspensa não altera mural nem remove arquivos")
    func deleteWhilePersistenceSuspendedPreservesBoardAndFiles() throws {
        let store = makeStore()
        try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: true)
        let model = BoardModel(store: store)
        let media = try #require(model.importData(Data([6, 7, 8]), fileExtension: "mov", kind: .video, title: "Clipe"))
        let file = try #require(model.fileURL(for: media))
        let boardBeforeDelete = model.board

        #expect(model.isPersistenceSuspended)
        model.delete(media.id)

        #expect(model.board == boardBeforeDelete)
        #expect(model.item(id: media.id) != nil)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(model.lastError != nil)
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

    @Test("Falha de leitura que não é corrupção não sobrescreve o mural salvo")
    func unreadableBoardIsNeverOverwritten() throws {
        let store = makeStore()
        // Uma pasta no lugar de board.json: a leitura falha sem ser um JSON corrompido.
        try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: true)
        let model = BoardModel(store: store)
        #expect(model.isPersistenceSuspended)
        #expect(model.lastError != nil)
        model.importText("Não deve ser gravado")
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue, "o caminho original continua intocado")
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
