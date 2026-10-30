import MuralKit
import Testing

@testable import Mural

@Suite("Textos e atalhos do editor de texto")
struct TextEditorWordingTests {
    @Test("A contagem de palavras usa o singular só para uma")
    func wordCount() {
        #expect(TextEditorWording.wordCount(0) == "0 palavras")
        #expect(TextEditorWording.wordCount(1) == "1 palavra")
        #expect(TextEditorWording.wordCount(12) == "12 palavras")
    }

    @Test("A barra e o menu oferecem as formatações menos \"como está\", e só quatro têm atalho, sem repetir")
    func formatsAndShortcuts() {
        let formats = TextEditorWording.formats
        #expect(!formats.contains(.original) && formats.count == PasteTextFormat.allCases.count - 1)
        let shortcuts = formats.compactMap(TextEditorWording.shortcut(for:))
        #expect(shortcuts.count == 4 && Set(shortcuts).count == 4)
        #expect(TextEditorWording.shortcut(for: .bulletList) == "l" && TextEditorWording.shortcut(for: .uppercase) == "u")
        #expect(TextEditorWording.shortcut(for: .tidy) == nil)
    }
}
