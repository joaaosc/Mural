import MuralKit
import SwiftUI

/// O que o menu Editar e o menu Formatar fazem no editor de texto, publicado enquanto a janela dele é a do foco.
struct TextEditorActions {
    let applyFormat: (PasteTextFormat) -> Void
    let applyEmphasis: (MarkdownEmphasis) -> Void
    let insertReminder: () -> Void
    let requestPaste: () -> Void
    /// Há texto para colar no mural.
    let canPaste: Bool
}

extension FocusedValues {
    /// Presente só enquanto a janela do editor de texto tem o foco.
    @Entry var textEditorActions: TextEditorActions?
}
