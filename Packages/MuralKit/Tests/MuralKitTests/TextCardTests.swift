import Foundation
import StretchText
import Testing

@testable import MuralKit

@MainActor
@Suite("Cartões de texto")
struct TextCardTests {
    private func makeModel() -> BoardModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MuralText-\(UUID().uuidString)")
        return BoardModel(store: BoardStore(directory: directory), seedIfEmpty: false)
    }

    @Test("Popup de colar: sugestão pelo classificador; Lista só quando o texto parece lista")
    func pasteChoice() {
        #expect(
            ContentClassifier.pasteChoice(forText: "Ligar para o marceneiro") == PasteChoice(suggested: .sticky, offersChecklist: false))
        let long = String(repeating: "palavra ", count: 40)
        #expect(ContentClassifier.pasteChoice(forText: long) == PasteChoice(suggested: .text, offersChecklist: false))
        let list = ContentClassifier.pasteChoice(forText: "Compras\n- pão\n- leite")
        #expect(list == PasteChoice(suggested: .checklist, offersChecklist: true))
        #expect(list.options == [.sticky, .text, .checklist])
        #expect(PasteChoice(suggested: .text, offersChecklist: false).options == [.sticky, .text])
    }

    @Test("Texto curto escolhido como card vira nota, não post-it")
    func explicitKind() throws {
        let importer = ItemImporter(itemsDirectory: FileManager.default.temporaryDirectory)
        let card = try importer.importText("Ligar para o marceneiro", as: .text)
        #expect(card.kind == .text)
        #expect(card.title == "Ligar para o marceneiro")
        let sticky = try importer.importText(String(repeating: "palavra ", count: 40), as: .sticky)
        #expect(sticky.kind == .sticky)
        #expect(sticky.stickyColor == .yellow)
        #expect(throws: ImportError.self) { try importer.importText("  \n", as: .text) }
    }

    @Test(
        "Título `#` na primeira linha vira o título e sai do corpo",
        arguments: [
            ("# Visita\n\nCorpo da nota.", "Visita", "Corpo da nota."),
            ("## Fecha ##\r\nCorpo.", "Fecha", "Corpo."),
            ("# Notas de C#\nx", "Notas de C#", "x"),
            ("# Só título", "Só título", nil),
        ] as [(String, String, String?)])
    func headingTitle(text: String, title: String, body: String?) throws {
        let card = try ItemImporter(itemsDirectory: FileManager.default.temporaryDirectory).importText(text, as: .text)
        #expect(card.title == title)
        #expect(card.text == body)
    }

    @Test("Sem `#`, o título é a primeira linha e o corpo continua inteiro")
    func plainTitle() throws {
        let card = try ItemImporter(itemsDirectory: FileManager.default.temporaryDirectory).importText("#hashtag\nresto", as: .text)
        #expect(card.title == "hashtag")
        #expect(card.text == "#hashtag\nresto")
    }

    @Test("Card e post-it novos nascem vazios; vazio é detectado para descarte")
    func createBlank() throws {
        let model = makeModel()
        let note = model.createNote()
        let sticky = model.createSticky(color: .pink)
        #expect(model.item(id: note.id)?.isBlank == true)
        #expect(model.item(id: sticky.id)?.stickyColor == .pink)
        #expect(model.item(id: sticky.id)?.isBlank == true)
        model.updateNote(note.id, title: "", text: "Corpo. Com duas frases.")
        #expect(model.item(id: note.id)?.isBlank == false)
        #expect(BoardItem(kind: .image, title: "").isBlank == false)
    }

    @Test("Editar a nota grava título e corpo; sem título, usa a primeira linha")
    func updateNote() throws {
        let model = makeModel()
        let note = model.createNote()
        model.updateNote(note.id, title: "  ", text: "# Visita\nCorpo.")
        #expect(model.item(id: note.id)?.title == "Visita")
        model.updateNote(note.id, title: "Outro", text: "  \n")
        #expect(model.item(id: note.id)?.title == "Outro")
        #expect(model.item(id: note.id)?.text == nil)
    }

    @Test("Mudar o corpo descarta as frases escolhidas; mudar só o título, não")
    func editingInvalidatesChoices() throws {
        let model = makeModel()
        let body = "Primeira frase. Segunda frase."
        let note = try #require(model.importText(body, as: .text))
        let record = KeySentenceRecord(
            source: body, choices: [0: SentenceChoice(sentenceID: SentenceID(segment: 0, index: 1), source: .model)])
        #expect(model.setKeySentences(record, for: note.id))
        model.updateNote(note.id, title: "Novo título", text: body)
        #expect(model.item(id: note.id)?.keySentences == record)
        model.updateNote(note.id, title: "Novo título", text: body + " Terceira.")
        #expect(model.item(id: note.id)?.keySentences == nil)
    }

    @Test("Escolha de um texto que mudou, ou de cartão sem texto dobrável, não é guardada")
    func rejectsStaleChoices() throws {
        let model = makeModel()
        let note = try #require(model.importText("Primeira frase. Segunda frase.", as: .text))
        let stale = KeySentenceRecord(source: "Outro texto. Outra frase.", choices: [:])
        #expect(!model.setKeySentences(stale, for: note.id))
        #expect(model.item(id: note.id)?.keySentences == nil)
        let sticky = try #require(model.importText("Curto. Mesmo.", as: .sticky))
        #expect(!model.setKeySentences(KeySentenceRecord(source: "Curto. Mesmo.", choices: [:]), for: sticky.id))
        #expect(!model.setKeySentences(stale, for: UUID()))
    }

    @Test("Post-it editado grava texto, cor e título pela primeira linha")
    func updateSticky() throws {
        let model = makeModel()
        let sticky = model.createSticky()
        model.updateSticky(sticky.id, text: "  Luz quente\nem tudo ", color: .green)
        let saved = try #require(model.item(id: sticky.id))
        #expect(saved.text == "Luz quente\nem tudo")
        #expect(saved.title == "Luz quente")
        #expect(saved.stickyColor == .green)
        model.updateNote(sticky.id, title: "x", text: "y")
        #expect(model.item(id: sticky.id)?.text == "Luz quente\nem tudo", "updateNote não mexe em post-it")
    }

    @Test("Notas e escolhas sobrevivem à reabertura")
    func persists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MuralText-\(UUID().uuidString)")
        let model = BoardModel(store: BoardStore(directory: directory), seedIfEmpty: false)
        let body = "Primeira frase. Segunda frase."
        let note = try #require(model.importText(body, as: .text))
        let record = KeySentenceRecord(
            source: body, choices: [0: SentenceChoice(sentenceID: SentenceID(segment: 0, index: 1), source: .model)])
        model.setKeySentences(record, for: note.id)
        let reopened = BoardModel(store: BoardStore(directory: directory), seedIfEmpty: false)
        #expect(reopened.item(id: note.id)?.keySentences == record)
    }
}
