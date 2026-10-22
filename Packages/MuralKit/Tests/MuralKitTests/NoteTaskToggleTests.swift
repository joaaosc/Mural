import Foundation
import StretchText
import Testing

@testable import MuralKit

@MainActor
@Suite("Tarefas na nota")
struct NoteTaskToggleTests {
    static let body = "- [ ] Pintar a porta\n- [x] Lixar o batente\n\nPrimeira frase. Segunda frase."

    private func makeStore() -> BoardStore {
        BoardStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent("MuralTasks-\(UUID().uuidString)"))
    }

    private func makeNote(store: BoardStore, text: String = body) throws -> (BoardModel, UUID) {
        let model = BoardModel(store: store, seedIfEmpty: false)
        let note = try #require(model.importText(text, as: .text))
        return (model, note.id)
    }

    @Test("Marca e desmarca a tarefa do bloco")
    func togglesBothWays() throws {
        let (model, id) = try makeNote(store: makeStore())
        #expect(model.toggleNoteTask(id, segment: 0, in: Self.body))
        let marked = "- [x] Pintar a porta\n- [x] Lixar o batente\n\nPrimeira frase. Segunda frase."
        #expect(model.item(id: id)?.text == marked)
        #expect(model.toggleNoteTask(id, segment: 2, in: marked))
        #expect(model.item(id: id)?.text == "- [x] Pintar a porta\n- [ ] Lixar o batente\n\nPrimeira frase. Segunda frase.")
    }

    @Test("A marca é gravada")
    func persists() throws {
        let store = makeStore()
        let (model, id) = try makeNote(store: store)
        #expect(model.toggleNoteTask(id, segment: 0, in: Self.body))
        let reloaded = BoardModel(store: store, seedIfEmpty: false)
        #expect(reloaded.item(id: id)?.text?.hasPrefix("- [x] Pintar a porta") == true)
    }

    @Test("As frases curtas continuam valendo para o texto novo")
    func keepsKeySentences() throws {
        let (model, id) = try makeNote(store: makeStore())
        let choice = SentenceChoice(sentenceID: SentenceID(segment: 4, index: 1), source: .model)
        let record = KeySentenceRecord(source: Self.body, choices: [4: choice])
        #expect(model.setKeySentences(record, for: id))
        #expect(model.toggleNoteTask(id, segment: 0, in: Self.body))
        let item = try #require(model.item(id: id))
        let text = try #require(item.text)
        let kept = try #require(item.keySentences)
        #expect(kept.matches(text))
        #expect(!kept.matches(Self.body))
        #expect(kept.choices == record.choices)
    }

    @Test("Texto desatualizado não muda nada")
    func staleSource() throws {
        let (model, id) = try makeNote(store: makeStore())
        #expect(!model.toggleNoteTask(id, segment: 0, in: Self.body + " Mais."))
        #expect(model.item(id: id)?.text == Self.body)
    }

    @Test("Bloco que não é tarefa não muda nada")
    func notATask() throws {
        let (model, id) = try makeNote(store: makeStore())
        #expect(!model.toggleNoteTask(id, segment: 4, in: Self.body))
        #expect(!model.toggleNoteTask(id, segment: 99, in: Self.body))
        #expect(model.item(id: id)?.text == Self.body)
    }

    @Test("Post-it e lista não aceitam")
    func otherKinds() throws {
        let model = BoardModel(store: makeStore(), seedIfEmpty: false)
        let sticky = try #require(model.importText("- [ ] Pintar", as: .sticky))
        #expect(!model.toggleNoteTask(sticky.id, segment: 0, in: "- [ ] Pintar"))
        #expect(model.item(id: sticky.id)?.text == "- [ ] Pintar")
        let list = try #require(model.importText("Compras\n- pão\n- leite", as: .checklist))
        #expect(!model.toggleNoteTask(list.id, segment: 0, in: list.text ?? ""))
    }

    @Test("Título e anexos continuam iguais")
    func keepsTitleAndAttachments() throws {
        let (model, id) = try makeNote(store: makeStore())
        let before = try #require(model.item(id: id))
        #expect(model.toggleNoteTask(id, segment: 0, in: Self.body))
        let after = try #require(model.item(id: id))
        #expect(after.title == before.title)
        #expect(after.attachments == before.attachments)
    }
}
