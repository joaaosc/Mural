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
}
