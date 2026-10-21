import Testing

@testable import MuralKit

@Suite("Negrito e itálico no editor")
struct MarkdownEmphasisTests {
    @Test(
        "Aplica e retira a ênfase em volta da seleção",
        arguments: [
            (MarkdownEmphasis.bold, "abc", 0..<3, "**abc**", 2..<5),
            (.bold, "**abc**", 2..<5, "abc", 0..<3),
            (.bold, "**abc**", 0..<7, "abc", 0..<3),
            (.italic, "abc", 0..<3, "*abc*", 1..<4),
            (.italic, "*abc*", 1..<4, "abc", 0..<3),
            (.italic, "**abc**", 2..<5, "***abc***", 3..<6),
            (.bold, "***abc***", 3..<6, "*abc*", 1..<4),
            (.italic, "***abc***", 3..<6, "**abc**", 2..<5),
            (.bold, "um dois três", 3..<7, "um **dois** três", 5..<9),
            (.bold, "ação", 0..<4, "**ação**", 2..<6),
        ] as [(MarkdownEmphasis, String, Range<Int>, String, Range<Int>)])
    func toggles(emphasis: MarkdownEmphasis, text: String, selection: Range<Int>, expected: String, expectedSelection: Range<Int>) {
        let result = emphasis.toggle(in: text, selection: selection)
        #expect(result.text == expected)
        #expect(result.selection == expectedSelection)
    }

    @Test("Cursor sem seleção: insere o par e fica no meio; entre um par vazio, retira")
    func insertionPoint() {
        let inserted = MarkdownEmphasis.bold.toggle(in: "x  y", selection: 2..<2)
        #expect(inserted.text == "x **** y")
        #expect(inserted.selection == 4..<4)
        let removed = MarkdownEmphasis.bold.toggle(in: inserted.text, selection: inserted.selection)
        #expect(removed.text == "x  y")
        #expect(removed.selection == 2..<2)
        #expect(MarkdownEmphasis.italic.toggle(in: "", selection: 0..<0).text == "**")
    }

    @Test("Seleção fora do texto é limitada ao texto")
    func clampsSelection() {
        let result = MarkdownEmphasis.bold.toggle(in: "abc", selection: 1..<99)
        #expect(result.text == "a**bc**")
        #expect(result.selection == 3..<5)
    }
}
