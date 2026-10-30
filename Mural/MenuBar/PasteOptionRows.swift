import MuralKit
import SwiftUI

/// Uma linha por maneira de colar o que está copiado no mural do centro; a escolhida leva o destaque e a dica do Return.
///
/// A dica ocupa o mesmo espaço em todas as linhas (só some da vista), para a largura delas não mudar ao trocar de escolha.
/// Os textos de cada linha vêm de `PasteDescription`: a de editar leva o nome do app de edição, e com uma edição pendente
/// ela continua a edição e há a de descartá-la.
struct PasteOptionRows: View {
    let options: [PasteOption]
    /// O índice da maneira escolhida em `options`.
    let selectedOption: Int
    let clipboard: ClipboardKind
    /// O nome do mural do centro, que recebe o que for colado.
    let boardName: String
    /// O nome do app que edita o conteúdo; `nil` quando não se sabe.
    let editorName: String?
    /// Há uma edição pendente: as linhas colam o conteúdo editado ou continuam a edição.
    let isEditing: Bool
    /// Escolhe a maneira do índice e cola.
    let choose: @MainActor (Int) -> Void

    @Namespace private var selectionPill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 2) {
            ForEach(options.enumerated(), id: \.element.id) { index, option in
                let isSelected = index == selectedOption
                let title = PasteDescription.title(
                    of: option, clipboard: clipboard, editorName: editorName, isEditing: isEditing)
                let summary = PasteDescription.summary(of: option, board: boardName)
                HStack(spacing: 6) {
                    PanelActionRow(
                        symbolName: PasteDescription.symbol(of: option),
                        title: title,
                        summary: summary,
                        isSelected: isSelected,
                        namespace: selectionPill,
                        help: "\(title) \(summary)",
                        accessibilityLabel: "\(title) \(summary)",
                        accessibilityHint: PasteDescription.accessibilityHint(
                            of: option, editorName: editorName, isEditing: isEditing),
                        action: { choose(index) }
                    )
                    .focusable(false)
                    .accessibilityIdentifier("menu-bar-paste-option-\(option.id)")

                    KeyHint(
                        symbol: "return", label: PasteDescription.returnHintLabel(of: option),
                        description: PasteDescription.returnHintDescription(
                            of: option, editorName: editorName, isEditing: isEditing),
                        isCompact: true
                    )
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(!isSelected)
                }
            }
        }
        .animation(PanelMotion.animation(PanelMotion.selection, reduceMotion: reduceMotion), value: selectedOption)
    }
}

#Preview("Texto com edição", traits: .fixedLayout(width: PanelMetrics.panelWidth, height: 190)) {
    let options = PasteOptions.options(for: .text("Comprar pão\n- leite\n- ovos"), allowsEditing: true)
    PasteOptionRows(
        options: options, selectedOption: PasteOptions.suggestedIndex(in: options) ?? 0,
        clipboard: .text("Comprar pão\n- leite\n- ovos"), boardName: "Compras", editorName: "TextEdit", isEditing: false,
        choose: { _ in }
    )
    .padding()
}

#Preview("Edição pendente", traits: .fixedLayout(width: PanelMetrics.panelWidth, height: 190)) {
    let options = PasteOptions.options(forEdited: .text("Comprar pão (editado)"))
    PasteOptionRows(
        options: options, selectedOption: 2, clipboard: .text("Comprar pão (editado)"), boardName: "Compras",
        editorName: "TextEdit", isEditing: true, choose: { _ in }
    )
    .padding()
}

#Preview("Imagem com edição", traits: .fixedLayout(width: PanelMetrics.panelWidth, height: 120)) {
    let options = PasteOptions.options(for: .image, allowsEditing: true)
    PasteOptionRows(
        options: options, selectedOption: 1, clipboard: .image, boardName: "Fotos", editorName: "Pré-Visualização",
        isEditing: false, choose: { _ in }
    )
    .padding()
}
