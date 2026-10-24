import Foundation
import Testing

@testable import MuralKit

// MARK: Fixtures

/// Ids fixos e legíveis: `id(3)` é sempre o mesmo.
private func id(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012ld", number))!
}

private func date(_ seconds: Double) -> Date {
    Date(timeIntervalSince1970: seconds)
}

/// Nome de anexo de nota (`<UUID>.<extensão>`), o formato que o texto da nota sabe citar.
private func attachmentName(_ number: Int) -> String {
    "\(id(number).uuidString).png"
}

private func attachment(_ number: Int) -> NoteAttachment {
    NoteAttachment(fileName: attachmentName(number), pixelWidth: 10, pixelHeight: 10)
}

/// A pasta "Viagem" com uma nota e uma subpasta (com outra nota), mais uma nota e uma foto soltas no trip.
private struct TripBoard {
    let folder = BoardItem(id: id(1), kind: .folder, title: "Viagem", createdAt: date(1), position: BoardPoint(x: 80, y: 80))
    let note: BoardItem
    let subfolder: BoardItem
    let deepNote: BoardItem
    let loose = BoardItem(
        id: id(5), kind: .text, title: "Solta", createdAt: date(5), position: BoardPoint(x: 300, y: 80), text: "Corpo")
    let photo = BoardItem(
        id: id(6), kind: .image, title: "Foto", createdAt: date(6), position: BoardPoint(x: 500, y: 80), fileName: "foto.png")

    init() {
        note = BoardItem(id: id(2), kind: .text, title: "Roteiro", createdAt: date(2), parentID: folder.id, text: "Dia 1")
        subfolder = BoardItem(id: id(3), kind: .folder, title: "Hotel", createdAt: date(3), parentID: folder.id)
        deepNote = BoardItem(id: id(4), kind: .text, title: "Reserva", createdAt: date(4), parentID: subfolder.id, text: "Quarto 12")
    }

    var board: Board { Board(items: [folder, note, subfolder, deepNote, loose, photo]) }
}

/// Um cartão com TODAS as propriedades opcionais preenchidas, pelos inicializadores reais de cada tipo.
private func fullItem() -> BoardItem {
    BoardItem(
        id: id(30), kind: .text, title: "Completo", createdAt: date(30), parentID: id(31), position: BoardPoint(x: 1, y: 2),
        fileName: "completo.png", text: "Corpo", caption: "Legenda",
        checklist: ChecklistDocument(
            title: "Lista", intro: "Abertura",
            sections: [ChecklistSection(id: id(32), title: "Seção", entries: [ChecklistEntry(id: id(33), text: "Item", isDone: true)])]),
        stickyColor: .pink,
        imageMetadata: ImageMetadata(
            pixelWidth: 10, pixelHeight: 20, fileSizeBytes: 30, colorProfile: "sRGB",
            palette: [PaletteColor(red: 0.1, green: 0.2, blue: 0.3)]),
        tag: "CLIENT 001",
        keySentences: KeySentenceRecord(source: "Corpo", choices: [:]),
        link: LinkInfo(url: URL(string: "https://apple.com")!, pageTitle: "Apple"),
        reminder: ReminderSnapshot(identifier: "R-1", title: "Lembrete"),
        music: MusicSnapshot(kind: .album, title: "Álbum"),
        colorTag: .red,
        attachments: [attachment(34)],
        folderPosition: BoardPoint(x: 3, y: 4),
        size: BoardSize(width: 200, height: 150))
}

// MARK: Campos

@Suite("Campos do cartão")
struct BoardItemFieldTests {
    @Test("As chaves do JSON de um cartão cheio são o id e os campos, nem mais nem menos")
    func fieldsMatchTheJSONKeys() throws {
        let data = try JSONEncoder().encode(fullItem())
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let expected = Set(BoardItem.Field.allCases.map(\.rawValue)).union(["id"])
        let difference = Set(object.keys).symmetricDifference(expected)
        #expect(difference.isEmpty, "propriedade de BoardItem sem BoardItem.Field (ou o contrário): \(difference.sorted())")
        #expect(BoardItem.Field.allCases.count == 20)
    }

    @Test("Os nomes das propriedades guardadas também são o id e os campos, mesmo que o cartão do teste não as preencha")
    func fieldsMatchTheStoredProperties() {
        let stored = Set(Mirror(reflecting: BoardItem(kind: .text, title: "")).children.compactMap(\.label))
        let expected = Set(BoardItem.Field.allCases.map(\.rawValue)).union(["id"])
        let difference = stored.symmetricDifference(expected)
        #expect(difference.isEmpty, "propriedade de BoardItem sem BoardItem.Field (ou o contrário): \(difference.sorted())")
    }

    @Test("Cartões iguais não têm campo diferente")
    func equalItemsHaveNoChangedFields() {
        #expect(fullItem().changedFields(from: fullItem()).isEmpty)
    }

    @Test("Cada campo é detectado sozinho quando só ele muda")
    func everyFieldIsDetectedAlone() {
        let base = fullItem()
        var edited: [BoardItem.Field: BoardItem] = [:]
        func edit(_ field: BoardItem.Field, _ change: (inout BoardItem) -> Void) {
            var copy = base
            change(&copy)
            edited[field] = copy
        }
        edit(.kind) { $0.kind = .sticky }
        edit(.title) { $0.title = "Outro título" }
        edit(.createdAt) { $0.createdAt = date(99) }
        edit(.parentID) { $0.parentID = id(99) }
        edit(.position) { $0.position = BoardPoint(x: 9, y: 9) }
        edit(.fileName) { $0.fileName = "outro.png" }
        edit(.text) { $0.text = "Outro corpo" }
        edit(.caption) { $0.caption = "Outra legenda" }
        edit(.checklist) { $0.checklist?.title = "Outra lista" }
        edit(.stickyColor) { $0.stickyColor = .green }
        edit(.imageMetadata) { $0.imageMetadata?.pixelWidth = 999 }
        edit(.tag) { $0.tag = "OUTRA" }
        edit(.keySentences) { $0.keySentences = KeySentenceRecord(source: "Outro corpo", choices: [:]) }
        edit(.link) { $0.link?.pageTitle = "Outra página" }
        edit(.reminder) { $0.reminder?.isCompleted = true }
        edit(.music) { $0.music?.title = "Outro álbum" }
        edit(.colorTag) { $0.colorTag = .blue }
        edit(.attachments) { $0.attachments = [] }
        edit(.folderPosition) { $0.folderPosition = nil }
        edit(.size) { $0.size = nil }

        #expect(Set(edited.keys) == Set(BoardItem.Field.allCases), "falta um caso neste teste")
        for (field, item) in edited {
            #expect(item.changedFields(from: base) == [field], "\(field.rawValue)")
            #expect(base.changedFields(from: item) == [field], "\(field.rawValue), ao contrário")
        }
    }

    @Test("Vários campos alterados saem juntos")
    func severalChangedFields() {
        var item = fullItem()
        item.title = "Novo"
        item.text = nil
        item.colorTag = nil
        #expect(item.changedFields(from: fullItem()) == [.title, .text, .colorTag])
    }
}

// MARK: Mudanças

@Suite("Mudanças entre dois murais")
struct BoardChangesTests {
    private let trip = TripBoard()

    private func changes(_ edit: (inout Board) -> Void) -> BoardChanges {
        var new = trip.board
        edit(&new)
        return BoardChanges.between(trip.board, new)
    }

    // MARK: Cartões

    @Test("Murais iguais não têm mudança nenhuma")
    func equalBoardsHaveNoChanges() {
        #expect(BoardChanges.between(trip.board, trip.board).isEmpty)
        #expect(BoardChanges.between(Board(), Board()).isEmpty)
        #expect(BoardChanges().isEmpty)
    }

    @Test("Cartão criado sai com todos os campos")
    func createdItemHasEveryField() {
        let created = BoardItem(id: id(20), kind: .sticky, title: "Novo", createdAt: date(20), text: "Oi")
        let result = changes { $0.add(created) }
        #expect(result == BoardChanges(savedItems: [created.id: Set(BoardItem.Field.allCases)]))
        #expect(!result.isEmpty)
    }

    @Test("Título editado muda só o título")
    func editedTitleChangesOnlyTheTitle() {
        var edited = trip.loose
        edited.title = "Renomeada"
        #expect(changes { $0.update(edited) } == BoardChanges(savedItems: [edited.id: [.title]]))
    }

    @Test("Cartão movido muda só a posição, mesmo indo para o fim da lista")
    func movedItemChangesOnlyThePosition() {
        var moved = trip.board
        moved.move(id: trip.loose.id, to: BoardPoint(x: 10, y: 10))
        #expect(moved.items.last?.id == trip.loose.id, "controle: mover leva o cartão para o fim da lista")
        #expect(BoardChanges.between(trip.board, moved) == BoardChanges(savedItems: [trip.loose.id: [.position]]))
    }

    @Test("Só a ordem da lista mudou: nada mudou")
    func reorderedListIsNotAChange() {
        var reversed = trip.board
        reversed.items.reverse()
        #expect(BoardChanges.between(trip.board, reversed).isEmpty)
        var rotated = trip.board
        rotated.items.append(rotated.items.removeFirst())
        #expect(BoardChanges.between(trip.board, rotated).isEmpty)
    }

    @Test("Cartão levado para fora da pasta muda o pai, a posição e o lugar livre")
    func movedOutOfAFolderChangesTheParentAndPositions() {
        let sticky = BoardItem(
            id: id(21), kind: .sticky, title: "Post-it", createdAt: date(21), parentID: trip.folder.id, text: "Oi",
            folderPosition: BoardPoint(x: 5, y: 5))
        var old = trip.board
        old.add(sticky)
        var new = old
        new.moveToBoard(id: sticky.id, at: BoardPoint(x: 200, y: 200))
        #expect(BoardChanges.between(old, new) == BoardChanges(savedItems: [sticky.id: [.parentID, .position, .folderPosition]]))
    }

    @Test("Vários cartões alterados e um criado saem cada um com os seus campos")
    func severalItemsEachWithItsOwnFields() {
        var renamed = trip.note
        renamed.title = "Outro roteiro"
        renamed.text = "Dia 2"
        var tagged = trip.folder
        tagged.tag = "VIAGEM"
        let created = BoardItem(id: id(22), kind: .sticky, title: "Novo", createdAt: date(22))
        let result = changes {
            $0.update(renamed)
            $0.update(tagged)
            $0.add(created)
        }
        #expect(
            result
                == BoardChanges(savedItems: [
                    renamed.id: [.title, .text], tagged.id: [.tag], created.id: Set(BoardItem.Field.allCases),
                ]))
    }

    @Test("Pasta apagada com o que tem dentro lista todos os cartões")
    func deletedFolderListsEveryDescendant() {
        let result = changes { $0.remove(id: trip.folder.id) }
        #expect(result == BoardChanges(deletedItemIDs: [trip.folder.id, trip.note.id, trip.subfolder.id, trip.deepNote.id]))
    }

    // MARK: Textos livres

    @Test("Texto livre criado, editado e apagado")
    func freeTexts() {
        let untouched = BoardFreeText(id: id(10), text: "Fica", position: BoardPoint(x: 10, y: 10), createdAt: date(1))
        let edited = BoardFreeText(id: id(11), text: "Antes", position: BoardPoint(x: 20, y: 20), createdAt: date(2))
        let moved = BoardFreeText(id: id(12), text: "Mexido", position: BoardPoint(x: 30, y: 30), createdAt: date(3))
        let deleted = BoardFreeText(id: id(13), text: "Some", position: BoardPoint(x: 40, y: 40), createdAt: date(4))
        let created = BoardFreeText(id: id(14), text: "Novo", position: BoardPoint(x: 50, y: 50), createdAt: date(5))
        let old = Board(items: trip.board.items, freeTexts: [untouched, edited, moved, deleted])

        var new = old
        new.update(BoardFreeText(id: edited.id, text: "Depois", position: edited.position, createdAt: edited.createdAt))
        new.moveFreeText(id: moved.id, to: BoardPoint(x: 31, y: 31))
        new.removeFreeText(id: deleted.id)
        new.add(created)

        #expect(
            BoardChanges.between(old, new)
                == BoardChanges(savedFreeTextIDs: [edited.id, moved.id, created.id], deletedFreeTextIDs: [deleted.id]))
        #expect(BoardChanges.between(old, old).isEmpty)
    }

    // MARK: Arquivos

    @Test("Cartão de imagem novo acrescenta o arquivo dele")
    func newImageCardAddsItsFile() {
        let image = BoardItem(id: id(23), kind: .image, title: "Nova", createdAt: date(23), fileName: "nova.png")
        let result = changes { $0.add(image) }
        #expect(result.addedFileNames == ["nova.png"])
        #expect(result.releasedFileNames.isEmpty)
        #expect(result == BoardChanges(savedItems: [image.id: Set(BoardItem.Field.allCases)], addedFileNames: ["nova.png"]))
    }

    @Test("Anexo novo de uma nota acrescenta o arquivo, esteja ou não citado no texto")
    func newNoteAttachmentAddsItsFile() {
        var withAttachment = trip.loose
        withAttachment.attachments = [attachment(40)]
        #expect(
            changes { $0.update(withAttachment) }
                == BoardChanges(savedItems: [withAttachment.id: [.attachments]], addedFileNames: [attachmentName(40)]))

        // Citado só no texto, sem entrar nos anexos (o texto também liga a nota ao arquivo).
        var citing = trip.loose
        citing.text = "Corpo\n\n" + NoteImageMarkup.line(fileName: attachmentName(41))
        #expect(
            changes { $0.update(citing) }
                == BoardChanges(savedItems: [citing.id: [.text]], addedFileNames: [attachmentName(41)]))
    }

    @Test("Cartão apagado libera o arquivo dele")
    func deletedCardReleasesItsFile() {
        let result = changes { $0.remove(id: trip.photo.id) }
        #expect(result == BoardChanges(deletedItemIDs: [trip.photo.id], releasedFileNames: ["foto.png"]))
    }

    @Test("Arquivo que outro cartão ainda cita não é liberado")
    func fileStillCitedByAnotherCardStays() {
        let name = attachmentName(42)
        var first = BoardItem(id: id(24), kind: .text, title: "Primeira", createdAt: date(24), text: "A")
        first.attachments = [attachment(42)]
        let second = BoardItem(
            id: id(25), kind: .text, title: "Segunda", createdAt: date(25), text: "B\n\n" + NoteImageMarkup.line(fileName: name))
        var old = trip.board
        old.add(first)
        old.add(second)

        var withoutFirst = old
        withoutFirst.remove(id: first.id)
        #expect(BoardChanges.between(old, withoutFirst) == BoardChanges(deletedItemIDs: [first.id]))

        var withoutBoth = withoutFirst
        withoutBoth.remove(id: second.id)
        #expect(BoardChanges.between(old, withoutBoth).releasedFileNames == [name])
    }

    @Test("Nota que deixa de citar a imagem no texto e nos anexos libera o arquivo")
    func noteDroppingTheImageReleasesTheFile() {
        let name = attachmentName(43)
        var note = trip.loose
        note.text = "Corpo\n\n" + NoteImageMarkup.line(fileName: name)
        note.attachments = [attachment(43)]
        var old = trip.board
        old.update(note)

        // Tirar a linha do texto não basta: o anexo ainda liga a nota ao arquivo.
        var onlyText = old
        note.text = "Corpo"
        onlyText.update(note)
        #expect(BoardChanges.between(old, onlyText) == BoardChanges(savedItems: [note.id: [.text]]))

        var both = onlyText
        note.attachments = nil
        both.update(note)
        #expect(BoardChanges.between(onlyText, both) == BoardChanges(savedItems: [note.id: [.attachments]], releasedFileNames: [name]))
    }

    @Test("Arquivo que muda de um cartão para outro não entra nem sai")
    func fileMovedBetweenCardsStays() {
        var old = trip.board
        var holder = trip.loose
        holder.attachments = [attachment(44)]
        old.update(holder)

        var new = old
        holder.attachments = nil
        new.update(holder)
        var receiver = BoardItem(id: id(26), kind: .text, title: "Outra", createdAt: date(26), text: "C")
        receiver.attachments = [attachment(44)]
        new.add(receiver)

        let result = BoardChanges.between(old, new)
        #expect(result.addedFileNames.isEmpty && result.releasedFileNames.isEmpty)
        #expect(Set(result.savedItems.keys) == [holder.id, receiver.id])
    }
}
