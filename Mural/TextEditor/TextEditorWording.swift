import MuralKit

/// Os textos do editor de texto que dependem de números e de formatações. Funções puras, para testar sem tela.
nonisolated enum TextEditorWording {
    /// "1 palavra", "12 palavras", "0 palavras".
    static func wordCount(_ count: Int) -> String {
        count == 1 ? "1 palavra" : "\(count) palavras"
    }

    /// As formatações do editor, na ordem da barra: todas as de `PasteTextFormat`, menos "como está".
    static var formats: [PasteTextFormat] {
        PasteTextFormat.allCases.filter { $0 != .original }
    }

    /// As formatações que ficam na barra, as quatro com atalho.
    static var toolbarFormats: [PasteTextFormat] {
        formats.filter { shortcut(for: $0) != nil }
    }

    /// As que ficam no menu "Mais formatações" da barra: as sem atalho.
    static var menuFormats: [PasteTextFormat] {
        formats.filter { shortcut(for: $0) == nil }
    }

    /// O atalho de menu da formatação, quando tem: ⌘⇧L lista, ⌘⇧T tarefas, ⌘⇧U maiúsculas, ⌘⇧K minúsculas.
    static func shortcut(for format: PasteTextFormat) -> Character? {
        switch format {
        case .bulletList: "l"
        case .taskList: "t"
        case .uppercase: "u"
        case .lowercase: "k"
        case .original, .tidy, .joinedLines: nil
        }
    }
}
