import MuralKit
import SwiftUI

/// Negrito e itálico do editor de Markdown com foco, para o menu Formatar.
struct MarkdownFormattingAction {
    let apply: (MarkdownEmphasis) -> Void
}

extension FocusedValues {
    /// Presente só enquanto o editor de Markdown de uma nota tem o foco.
    @Entry var markdownFormatting: MarkdownFormattingAction?
}
