import Foundation
import Testing

@testable import MuralKit

@MainActor
@Suite("URL de imagem de nota")
struct NoteImageURLTests {
    @Test("Nome de anexo seguro resolve para Items/; nome inseguro não")
    func resolvesOnlySafeNames() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MuralKitNoteImage-\(UUID().uuidString)")
        let model = BoardModel(store: BoardStore(directory: root), seedIfEmpty: false)
        let name = "\(UUID().uuidString).png"
        let url = try #require(model.noteImageURL(named: name))
        #expect(url.lastPathComponent == name)
        #expect(url.deletingLastPathComponent().lastPathComponent == "Items")
        #expect(model.noteImageURL(named: "../segredo.png") == nil)
        #expect(model.noteImageURL(named: "https://exemplo.com/a.png") == nil)
        #expect(model.noteImageURL(named: "") == nil)
    }
}
