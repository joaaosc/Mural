import Foundation
import Testing

@testable import MuralKit

@MainActor
@Suite("Criar pasta")
struct FolderCreationTests {
    private func makeModel() -> BoardModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MuralFolder-\(UUID().uuidString)")
        return BoardModel(store: BoardStore(directory: directory), seedIfEmpty: false)
    }

    @Test("Pasta nova fica solta no mural, com o nome sem espaços nas pontas")
    func createsRootFolder() {
        let model = makeModel()
        let folder = model.createFolder(named: "  Viagem  ")
        #expect(folder.kind == .folder)
        #expect(folder.title == "Viagem")
        #expect(folder.parentID == nil)
        #expect(model.rootItems.map(\.id) == [folder.id])
    }

    @Test("Sem nome, a pasta se chama Nova pasta")
    func defaultName() {
        #expect(makeModel().createFolder(named: " \n ").title == "Nova pasta")
    }

    @Test("A pasta nova não cobre o cartão que já estava no mural e recebe cartões")
    func placementAndContents() {
        let model = makeModel()
        let note = model.createNote()
        let folder = model.createFolder(named: "Referências")
        let noteSize = BoardLayout.cardSize(for: .text)
        let folderSize = BoardLayout.cardSize(for: .folder)
        let noteRect = CGRect(x: note.position.x, y: note.position.y, width: noteSize.width, height: noteSize.height)
        let folderRect = CGRect(
            x: folder.position.x, y: folder.position.y, width: folderSize.width, height: folderSize.height)
        #expect(!noteRect.intersects(folderRect))

        model.moveIntoFolder(note.id, folderID: folder.id)
        #expect(model.children(of: folder.id).map(\.id) == [note.id])
    }

    @Test("Renomear corta os espaços das pontas")
    func renamesAndTrims() {
        let model = makeModel()
        let folder = model.createFolder(named: "Viagem")
        #expect(model.renameFolder(folder.id, to: "  Trabalho \n"))
        #expect(model.board.item(id: folder.id)?.title == "Trabalho")
    }

    @Test("Nome vazio ou só com espaços não muda a pasta")
    func renameEmptyKeepsTitle() {
        let model = makeModel()
        let folder = model.createFolder(named: "Viagem")
        #expect(!model.renameFolder(folder.id, to: ""))
        #expect(!model.renameFolder(folder.id, to: " \n "))
        #expect(model.board.item(id: folder.id)?.title == "Viagem")
    }

    @Test("Mesmo nome devolve false")
    func renameSameName() {
        let model = makeModel()
        let folder = model.createFolder(named: "Viagem")
        #expect(!model.renameFolder(folder.id, to: " Viagem "))
    }

    @Test("Item que não é pasta não é renomeado")
    func renameIgnoresNonFolder() {
        let model = makeModel()
        let note = model.createNote()
        let title = model.board.item(id: note.id)?.title
        #expect(!model.renameFolder(note.id, to: "Outro"))
        #expect(model.board.item(id: note.id)?.title == title)
        #expect(!model.renameFolder(UUID(), to: "Outro"))
    }

    @Test("O novo nome fica gravado no disco")
    func renamePersists() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MuralFolder-\(UUID().uuidString)")
        let model = BoardModel(store: BoardStore(directory: directory), seedIfEmpty: false)
        let folder = model.createFolder(named: "Viagem")
        model.renameFolder(folder.id, to: "Trabalho")
        let reloaded = BoardModel(store: BoardStore(directory: directory), seedIfEmpty: false)
        #expect(reloaded.board.item(id: folder.id)?.title == "Trabalho")
    }
}
