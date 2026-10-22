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
}
