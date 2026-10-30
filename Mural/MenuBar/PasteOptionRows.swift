import MuralKit
import SwiftUI

/// Uma linha por maneira de colar o que está copiado no mural do centro; a escolhida leva o destaque e a dica do Return.
///
/// A dica ocupa o mesmo espaço em todas as linhas (só some da vista), para a largura delas não mudar ao trocar de escolha.
struct PasteOptionRows: View {
    let options: [PasteOption]
    /// O índice da maneira escolhida em `options`.
    let selectedOption: Int
    let clipboard: ClipboardKind
    /// O nome do mural do centro, que recebe o que for colado.
    let boardName: String
    /// Escolhe a maneira do índice e cola.
    let choose: @MainActor (Int) -> Void

    @Namespace private var selectionPill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let destination = "em \(boardName)"
        VStack(spacing: 2) {
            ForEach(options.enumerated(), id: \.element.id) { index, option in
                let isSelected = index == selectedOption
                let title = PasteDescription.title(of: option, clipboard: clipboard)
                HStack(spacing: 6) {
                    PanelActionRow(
                        symbolName: PasteDescription.symbol(of: option),
                        title: title,
                        summary: destination,
                        isSelected: isSelected,
                        namespace: selectionPill,
                        help: "\(title) \(destination)",
                        accessibilityLabel: "\(title) \(destination)",
                        accessibilityHint: "Cola o que foi copiado no mural do centro da vitrine.",
                        action: { choose(index) }
                    )
                    .focusable(false)
                    .accessibilityIdentifier("menu-bar-paste-option-\(option.id)")

                    KeyHint(symbol: "return", label: "Colar", description: "Return cola o que foi copiado", isCompact: true)
                        .opacity(isSelected ? 1 : 0)
                        .accessibilityHidden(!isSelected)
                }
            }
        }
        .animation(PanelMotion.animation(PanelMotion.selection, reduceMotion: reduceMotion), value: selectedOption)
    }
}
