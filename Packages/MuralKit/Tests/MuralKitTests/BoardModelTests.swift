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

    @Test("Destinos memoizados são invalidados quando o mural muda")
    func folderDestinationsCacheInvalidatesAfterBoardChange() throws {
        let model = BoardModel(store: makeStore(), seedIfEmpty: false)
        let card = try #require(model.importText("Cartão"))
        let first = model.createFolder(named: "Primeira")

        #expect(model.folderDestinations(for: card.id).map(\.id) == [first.id])

        let second = model.createFolder(named: "Segunda")
        #expect(model.folderDestinations(for: card.id).map(\.id) == [first.id, second.id])
    }

    @Test("Cartões comuns no mesmo pai reutilizam destinos")
    func nonFolderFolderDestinationsShareParentResult() throws {
        let model = BoardModel(store: makeStore(), seedIfEmpty: false)
        let parent = model.createFolder(named: "Pai")
        let first = try #require(model.importText("Primeiro", into: parent.id))
        let second = try #require(model.importText("Segundo", into: parent.id))
        let destination = model.createFolder(named: "Destino")

        #expect(model.folderDestinations(for: first.id).map(\.id) == [destination.id])
        #expect(model.folderDestinations(for: second.id).map(\.id) == [destination.id])
    }

    @Test("Leituras derivadas memoizadas são invalidadas quando o mural muda")
    func derivedReadCachesInvalidateAfterBoardChange() throws {
        let model = BoardModel(store: makeStore(), seedIfEmpty: false)
        let folder = model.createFolder(named: "Pasta")

        #expect(model.rootItems.count == 1)
        #expect(model.children(of: folder.id).isEmpty)
        #expect(model.freeTexts.isEmpty)
        #expect(model.rootItemSizes.count == model.rootItems.count)
        #expect(model.freeTextSizes.isEmpty)
        #expect(model.reminderItems.isEmpty)
        #expect(model.item(id: folder.id)?.title == "Pasta")
        let initialExtent = model.rootExtent

        let card = try #require(model.importText("Cartão", into: folder.id))
        let freeText = model.createFreeText("Texto", at: BoardPoint(x: 1_000, y: 1_000))
        let reminder = try #require(
            model.addReminders([ReminderSnapshot(identifier: "reminder", title: "Lembrete")]).first)

        #expect(model.rootItems.map(\.id) == [folder.id, reminder.id])
        #expect(model.children(of: folder.id).map(\.id) == [card.id])
        #expect(model.freeTexts.map(\.id) == [freeText.id])
        #expect(model.rootItemSizes.count == model.rootItems.count)
        #expect(model.freeTextSizes.count == model.freeTexts.count)
        #expect(model.item(id: card.id)?.title == "Cartão")
        #expect(model.reminderItems.map(\.id) == [reminder.id])
        #expect(model.rootExtent != initialExtent)
    }

    @Test("Snapshots de tamanho refletem redimensionamento do mural")
    func sizeSnapshotsInvalidateAfterResize() throws {
        let model = BoardModel(store: makeStore(), seedIfEmpty: false)
        let freeText = model.createFreeText("Texto")
        let initial = try #require(model.freeTextSizes[freeText.id])
        let resized = BoardSize(width: 260, height: 120)

        #expect(initial != resized)
        #expect(model.resizeFreeText(freeText.id, to: resized))
        #expect(model.freeTextSizes[freeText.id] == resized)
    }

    @Test("Extensão e snapshots compartilham dimensões e invalidam juntos")
    func sizeSnapshotsAndExtentShareRevision() throws {
        let model = BoardModel(store: makeStore(), seedIfEmpty: false)
        let item = try #require(model.importText("Cartão"))
        let freeText = model.createFreeText("Texto", at: BoardPoint(x: 1_000, y: 1_000))
        let itemSize = try #require(model.rootItemSizes[item.id])
        let freeTextSize = try #require(model.freeTextSizes[freeText.id])
        let initialExtent = model.rootExtent
        let expected = BoardSize(
            width: max(item.position.x + itemSize.width, freeText.position.x + freeTextSize.width),
            height: max(item.position.y + itemSize.height, freeText.position.y + freeTextSize.height))

        #expect(initialExtent == expected)

        let replacement = BoardSize(width: 320, height: 140)
        #expect(model.resizeFreeText(freeText.id, to: replacement))
        #expect(model.freeTextSizes[freeText.id] == replacement)
        #expect(
            model.rootExtent
                == BoardSize(
                    width: max(item.position.x + itemSize.width, freeText.position.x + replacement.width),
                    height: max(item.position.y + itemSize.height, freeText.position.y + replacement.height)
                )
        )
    }

    @Test("Cache de folding acompanha mudanças no texto")
    func foldedTextCacheInvalidatesAfterTextChange() throws {
        let model = BoardModel(store: makeStore(), seedIfEmpty: false)
        let note = model.createNote()
        model.updateNote(note.id, title: "Nota", text: "Primeira frase. Segunda frase.")
        let firstItem = try #require(model.item(id: note.id))
        let first = try #require(model.foldedText(for: firstItem))

        model.updateNote(note.id, title: "Nota", text: "Texto novo. Outra frase.")
        let updatedItem = try #require(model.item(id: note.id))
        let updated = try #require(model.foldedText(for: updatedItem))

        #expect(first != updated)
    }

    @Test("A revisão do board avança sem comparação estrutural")
    func boardRevisionAdvancesOnMutation() throws {
        let model = BoardModel(store: makeStore(), seedIfEmpty: false)
        let initial = model.boardRevision

        _ = try model.importText("Cartão")
        #expect(model.boardRevision == initial + 1)

        _ = model.createFreeText("Texto", at: BoardPoint(x: 100, y: 100))
        #expect(model.boardRevision == initial + 2)
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

    @Test("Exclusão deferred retém assets até o snapshot ser publicado")
    func deferredDeleteRetainsAssetUntilFinalize() throws {
        let model = BoardModel(store: makeStore(), persistence: .deferred)
        let media = try #require(model.importData(Data([9, 8, 7]), fileExtension: "mov", kind: .video, title: "Clipe"))
        let file = try #require(model.fileURL(for: media))
        #expect(FileManager.default.fileExists(atPath: file.path))

        model.delete(media.id)
        #expect(model.item(id: media.id) == nil)
        #expect(FileManager.default.fileExists(atPath: file.path))

        // A failed session flush does not call this finalization boundary.
        model.finalizeDeferredDeletions()
        #expect(!FileManager.default.fileExists(atPath: file.path))
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
        let loose = try #require(model.rootItems.first { $0.kind == .text })
        let child = try #require(model.children(of: folder.id).first)
        let boardBeforeMoves = model.board

        // Com uma pasta no lugar do board.json, qualquer gravação falharia e preencheria `lastError`.
        try FileManager.default.removeItem(at: store.fileURL)
        try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: true)

        model.move(child.id, to: BoardPoint(x: 10, y: 10))
        model.move(UUID(), to: BoardPoint(x: 10, y: 10))
        model.moveIntoFolder(folder.id, folderID: folder.id)
        model.moveIntoFolder(child.id, folderID: folder.id)
        model.moveIntoFolder(loose.id, folderID: child.id)
        model.moveIntoFolder(loose.id, folderID: loose.id)
        model.moveToBoard(loose.id)
        model.moveToBoard(UUID())
        #expect(model.board == boardBeforeMoves)
        #expect(model.lastError == nil)

        model.move(loose.id, to: BoardPoint(x: 10, y: 10))
        #expect(model.lastError != nil, "controle: um movimento válido tenta gravar")
    }
}
