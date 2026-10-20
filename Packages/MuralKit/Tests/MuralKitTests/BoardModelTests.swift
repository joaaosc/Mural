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

    @Test("Mover cartão grava posição e ordem e reaparece igual ao reabrir")
    func moveCardPersists() throws {
        let store = makeStore()
        let model = BoardModel(store: store)
        let card = try #require(model.rootItems.first { $0.kind == .text })
        let target = BoardPoint(x: 512, y: 384)
        model.move(card.id, to: target)
        #expect(model.lastError == nil)
        #expect(model.item(id: card.id)?.position == target)
        #expect(model.board.items.last?.id == card.id)

        let reopened = BoardModel(store: store)
        #expect(reopened.item(id: card.id)?.position == target)
        #expect(reopened.board.items.map(\.id) == model.board.items.map(\.id))
        #expect(reopened.board.items.map(\.position) == model.board.items.map(\.position))
    }

    @Test("Posição negativa é limitada a 0 e a fracionária é arredondada")
    func moveClampsPosition() throws {
        let store = makeStore()
        let model = BoardModel(store: store)
        let card = try #require(model.rootItems.first { $0.kind == .sticky })
        model.move(card.id, to: BoardPoint(x: -75.5, y: -3))
        #expect(model.item(id: card.id)?.position == .zero)

        model.move(card.id, to: BoardPoint(x: 120.6, y: -0.2))
        #expect(model.item(id: card.id)?.position == BoardPoint(x: 121, y: 0))
        let reopened = BoardModel(store: store)
        #expect(reopened.item(id: card.id)?.position == BoardPoint(x: 121, y: 0))
    }

    @Test("Guardar em pasta grava e o cartão reaparece dentro da pasta ao reabrir")
    func moveIntoFolderPersists() throws {
        let store = makeStore()
        let model = BoardModel(store: store)
        let folder = try #require(model.rootItems.first { $0.kind == .folder })
        let card = try #require(model.rootItems.first { $0.kind == .text })
        model.moveIntoFolder(card.id, folderID: folder.id)
        #expect(model.lastError == nil)
        #expect(model.children(of: folder.id).contains { $0.id == card.id })
        #expect(!model.rootItems.contains { $0.id == card.id })

        let reopened = BoardModel(store: store)
        #expect(reopened.children(of: folder.id).contains { $0.id == card.id })
        #expect(!reopened.rootItems.contains { $0.id == card.id })
    }

    @Test("Tirar da pasta solta o cartão numa posição livre e grava")
    func moveToBoardPersists() throws {
        let store = makeStore()
        let model = BoardModel(store: store)
        let folder = try #require(model.rootItems.first { $0.kind == .folder })
        let card = try #require(model.children(of: folder.id).first)
        model.moveToBoard(card.id)
        #expect(model.lastError == nil)
        let placed = try #require(model.item(id: card.id))
        #expect(placed.parentID == nil)
        #expect(model.board.items.last?.id == card.id)
        let size = BoardLayout.cardSize(for: placed.kind)
        for other in model.rootItems where other.id != placed.id {
            let otherSize = BoardLayout.cardSize(for: other.kind)
            #expect(!BoardLayout.overlaps(placed.position, size, other.position, otherSize, gap: 0), "colide com \(other.title)")
        }

        let reopened = BoardModel(store: store)
        let saved = try #require(reopened.item(id: card.id))
        #expect(saved.parentID == nil)
        #expect(saved.position == placed.position)
        #expect(!reopened.children(of: folder.id).contains { $0.id == card.id })
    }

    @Test("Movimento recusado não altera o mural nem tenta gravar")
    func rejectedMovesDoNotPersist() throws {
        let store = makeStore()
        let model = BoardModel(store: store)
        let folder = try #require(model.rootItems.first { $0.kind == .folder })
        let otherFolder = try #require(model.rootItems.last { $0.kind == .folder })
        let loose = try #require(model.rootItems.first { $0.kind == .text })
        let child = try #require(model.children(of: folder.id).first)
        let boardBeforeMoves = model.board

        // Com uma pasta no lugar do board.json, qualquer gravação falharia e preencheria `lastError`.
        try FileManager.default.removeItem(at: store.fileURL)
        try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: true)

        model.move(child.id, to: BoardPoint(x: 10, y: 10))
        model.move(UUID(), to: BoardPoint(x: 10, y: 10))
        model.moveIntoFolder(folder.id, folderID: otherFolder.id)
        model.moveIntoFolder(loose.id, folderID: loose.id)
        model.moveToBoard(loose.id)
        model.moveToBoard(UUID())
        #expect(model.board == boardBeforeMoves)
        #expect(model.lastError == nil)

        model.move(loose.id, to: BoardPoint(x: 10, y: 10))
        #expect(model.lastError != nil, "controle: um movimento válido tenta gravar")
    }
}
