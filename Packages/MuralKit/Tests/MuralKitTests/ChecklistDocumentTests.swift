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
        let doc = ChecklistDocument.parse(text)
        #expect(doc.title == "Things I need")
        #expect(doc.intro == "Lorem ipsum dolor sit amet.")
        #expect(doc.sections.map(\.title) == ["Living Room", "Kitchen"])
        #expect(doc.sections[0].entries.map(\.text) == ["Sofa", "Rug"])
        #expect(doc.sections[0].entries[1].isDone)
        #expect(doc.progress == (1, 3))
    }

    @Test("Lista sem título ganha seção anônima e título padrão")
    func parsesBareList() {
        let doc = ChecklistDocument.parse("- a\n- b")
        #expect(doc.title == "Lista")
        #expect(doc.sections.count == 1)
        #expect(doc.sections[0].title.isEmpty)
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
