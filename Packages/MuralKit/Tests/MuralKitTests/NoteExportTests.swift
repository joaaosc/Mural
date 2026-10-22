import Foundation
import Testing

@testable import MuralKit

@Suite("NoteExport")
struct NoteExportTests {
    private func note(_ text: String, title: String = "") -> BoardItem {
        BoardItem(kind: .text, title: title, text: text)
    }

    @Test("nota começa pelo título")
    func title() {
        let blocks = NoteExport.blocks(for: note("Olá", title: "Ideias"))
        #expect(blocks == [.title("Ideias"), .paragraph("Olá")])
    }

    @Test("nota sem título não gera bloco de título")
    func noTitle() {
        #expect(NoteExport.blocks(for: note("Olá")) == [.paragraph("Olá")])
    }

    @Test("cabeçalhos, listas e tarefas")
    func structure() {
        let text = "# Um\n\n## Dois\n\n- a\n- b\n\n1. x\n\n- [x] feito\n- [ ] aberto"
        let blocks = NoteExport.blocks(for: note(text))
        #expect(blocks.contains(.heading(level: 1, text: "Um")))
        #expect(blocks.contains(.heading(level: 2, text: "Dois")))
        #expect(blocks.contains(.listItem(marker: .bullet, depth: 0, text: "a")))
        #expect(blocks.contains(.listItem(marker: .ordered(1), depth: 0, text: "x")))
        #expect(blocks.contains(.listItem(marker: .task(done: true), depth: 0, text: "feito")))
        #expect(blocks.contains(.listItem(marker: .task(done: false), depth: 0, text: "aberto")))
    }

    @Test("citação, código, tabela, imagem e separador")
    func others() {
        let text = "> dito\n\n```swift\nlet a = 1\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n![Foto](x.png)\n\n---"
        let blocks = NoteExport.blocks(for: note(text))
        #expect(blocks.contains(.quote("dito")))
        #expect(blocks.contains(.code("let a = 1")))
        #expect(blocks.contains { if case .code(let t) = $0 { t.contains("| 1 | 2 |") } else { false } })
        #expect(blocks.contains(.image(fileName: "x.png", alt: "Foto")))
        #expect(blocks.last == .rule)
    }

    @Test("parágrafo dobrável sai inteiro")
    func foldableParagraphIsWhole() {
        let paragraph = "Primeira frase do texto. Segunda frase do texto. Terceira frase do texto."
        #expect(NoteExport.blocks(for: note(paragraph)) == [.paragraph(paragraph)])
    }

    @Test("post-it sai como um parágrafo com o texto")
    func sticky() {
        let item = BoardItem(kind: .sticky, title: "T", text: "Comprar **pão**")
        #expect(NoteExport.blocks(for: item) == [.paragraph("Comprar **pão**")])
    }

    @Test("lista: título, abertura, seções e tarefas")
    func checklist() {
        let document = ChecklistDocument(
            title: "Mercado",
            intro: "Para sábado",
            sections: [
                ChecklistSection(
                    title: "Frutas",
                    entries: [ChecklistEntry(text: "Maçã", isDone: true), ChecklistEntry(text: "Uva")])
            ])
        let item = BoardItem(kind: .checklist, title: "Mercado", checklist: document)
        #expect(
            NoteExport.blocks(for: item) == [
                .title("Mercado"), .paragraph("Para sábado"), .heading(level: 2, text: "Frutas"),
                .listItem(marker: .task(done: true), depth: 0, text: "Maçã"),
                .listItem(marker: .task(done: false), depth: 0, text: "Uva"),
            ])
    }
}
