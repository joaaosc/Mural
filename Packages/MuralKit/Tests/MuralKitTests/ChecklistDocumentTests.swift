import Foundation
import Testing

@testable import MuralKit

@Suite("Lista de itens")
struct ChecklistDocumentTests {
    @Test("Texto com título, introdução e seções é interpretado")
    func parsesSections() {
        let text = """
            Things I need
            Lorem ipsum dolor sit amet.
            Living Room
            - Sofa
            - [x] Rug
            Kitchen
            • Stools
            """
        let doc = ChecklistParser.parse(text)
        #expect(doc.title == "Things I need")
        #expect(doc.intro == "Lorem ipsum dolor sit amet.")
        #expect(doc.sections.map(\.title) == ["Living Room", "Kitchen"])
        #expect(doc.sections[0].entries.map(\.text) == ["Sofa", "Rug"])
        #expect(doc.sections[0].entries[1].isDone)
        #expect(doc.progress == (1, 3))
    }

    @Test("Lista sem título ganha seção anônima e título padrão")
    func parsesBareList() {
        let doc = ChecklistParser.parse("- a\n- b")
        #expect(doc.title == "Lista")
        #expect(doc.sections.count == 1)
        #expect(doc.sections[0].title.isEmpty)
    }

    @Test("Lista sem itens tem progresso vazio")
    func emptyProgress() {
        let doc = ChecklistDocument(title: "Vazia", sections: [])
        #expect(doc.progress == (0, 0))
    }

    @Test("Título só com # usa o título padrão e itens antes do título ficam sem seção")
    func edgeCases() {
        let doc = ChecklistParser.parse("- primeiro\n#\n- segundo")
        #expect(doc.title == "Lista")
        #expect(doc.sections.count == 1)
        #expect(doc.sections[0].entries.map(\.text) == ["primeiro", "segundo"])
    }

    @Test("Linha longa antes das seções vira introdução; curta vira seção")
    func introVersusSection() {
        let long = String(repeating: "palavra ", count: 8)
        let doc = ChecklistParser.parse("Compras\n\(long)\nMercado\n- pão\n- leite")
        #expect(doc.intro == long.trimmingCharacters(in: .whitespaces))
        #expect(doc.sections.map(\.title) == ["Mercado"])
    }

    @Test("Lista escrita em texto volta igual ao ser lida")
    func formatRoundTrip() {
        var original = SampleBoard.thingsINeed
        original.toggle(entryID: original.sections[0].entries[0].id)
        let text = ChecklistParser.format(original)
        #expect(ContentClassifier.kind(forText: text) == .checklist)
        let parsed = ChecklistParser.parse(text)
        #expect(parsed.title == original.title)
        #expect(parsed.intro == original.intro)
        #expect(parsed.sections.map(\.title) == original.sections.map(\.title))
        #expect(parsed.progress == original.progress)
    }

    @Test("Marcar e desmarcar um item")
    func toggles() {
        var doc = SampleBoard.thingsINeed
        let id = doc.sections[0].entries[0].id
        doc.toggle(entryID: id)
        #expect(doc.sections[0].entries[0].isDone)
        doc.toggle(entryID: id)
        #expect(!doc.sections[0].entries[0].isDone)
        doc.toggle(entryID: UUID())  // id inexistente não muda nada
        #expect(doc.progress.done == 0)
    }

    // MARK: Outros marcadores

    @Test("Lista numerada, com +, ◦ e ▪, é reconhecida e lida; `1-`, `-5`, anos, datas e falas não são marcadores")
    func parsesOrderedAndOtherMarkers() {
        let text = "Obra\n1. Reboco\n2) Pintura\n10. Limpeza\n+ Extra\n◦ Outro\n▪ Mais"
        #expect(ChecklistParser.looksLikeChecklist(text))
        let entries = ChecklistParser.parse(text).sections.flatMap(\.entries).map(\.text)
        #expect(entries == ["Reboco", "Pintura", "Limpeza", "Extra", "Outro", "Mais"])

        #expect(!ChecklistParser.looksLikeChecklist("2024. Foi um ano longo.\n2025. Foi outro ano."))
        #expect(!ChecklistParser.looksLikeChecklist("12. de abril\n13. de abril"))
        #expect(!ChecklistParser.looksLikeChecklist("– Oi.\n– Tudo bem?"))
        let email = (["Olá,", "1. Primeiro ponto", "2. Segundo ponto"] + (0..<27).map { "Linha de texto \($0)" }).joined(separator: "\n")
        #expect(!ChecklistParser.looksLikeChecklist(email))
        #expect(ChecklistParser.looksLikeChecklist("•\tItem\n•\tOutro"))
        #expect(ChecklistParser.looksLikeChecklist("1.\tItem\n2.\tOutro"))
        #expect(ChecklistParser.looksLikeChecklist("1. Comprar pão\n2. Leite"))
        #expect(ChecklistParser.looksLikeChecklist("10. Dez\n11. Onze"))
        #expect(ChecklistParser.looksLikeChecklist("1) Um\n2) Dois"))
        #expect(ChecklistParser.parse("•\t  Item\n•\tOutro").sections.flatMap(\.entries).map(\.text).first == "Item")

        #expect(!ChecklistParser.looksLikeChecklist("1- um\n2- dois"))
        #expect(!ChecklistParser.looksLikeChecklist("-5 graus\n-3 graus"))
        #expect(!ChecklistParser.looksLikeChecklist("1. só uma linha"))
        #expect(!ChecklistParser.looksLikeChecklist("1.5 litros\n2.5 litros"))
    }

    @Test("Marcadores misturados e caixas de tarefa continuam lendo o estado de marcado")
    func mixedMarkersKeepDoneState() {
        let entries = ChecklistParser.parse("Mercado\n- [x] Pão\n1. [ ] Leite\n[x] Café\n• Chá").sections.flatMap(\.entries)
        #expect(entries.map(\.text) == ["Pão", "Leite", "Café", "Chá"])
        #expect(entries.map(\.isDone) == [true, false, true, false])
    }

    @Test("O ⌘V classifica a lista numerada como lista")
    func orderedListIsAChecklistOnPaste() {
        #expect(ContentClassifier.kind(forText: "1. a\n2. b") == .checklist)
    }

    @Test("Títulos de seção que parecem item vão com ## e voltam; item vazio volta item vazio")
    func headingsAndEmptyEntriesRoundTrip() {
        let document = ChecklistDocument(
            title: "Obra", intro: "",
            sections: [
                ChecklistSection(title: "1. Cozinha", entries: [ChecklistEntry(text: "Pia", isDone: true)]),
                ChecklistSection(title: "+ Extras", entries: [ChecklistEntry(text: "", isDone: false)]),
                ChecklistSection(title: "Sala", entries: [ChecklistEntry(text: "Sofá", isDone: false)]),
            ])
        let text = ChecklistParser.format(document)
        #expect(text.contains("## 1. Cozinha") && text.contains("## + Extras") && !text.contains("## Sala"))
        let parsed = ChecklistParser.parse(text)
        #expect(parsed.title == "Obra")
        #expect(parsed.sections.map(\.title) == ["1. Cozinha", "+ Extras", "Sala"])
        #expect(parsed.sections.map { $0.entries.map(\.text) } == [["Pia"], [""], ["Sofá"]])
        #expect(parsed.sections.map { $0.entries.map(\.isDone) } == [[true], [false], [false]])
    }
}
