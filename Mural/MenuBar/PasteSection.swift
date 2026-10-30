import MuralKit
import SwiftUI

/// A seção do painel entre a vitrine e o rodapé, que muda com a etapa do teclado (``PanelStage``):
/// - na vitrine, só a linha "Copiado", com a dica do Tab: nenhuma maneira de colar fica escolhida;
/// - nas maneiras de colar, a linha "Copiado" e uma linha por maneira, com a escolhida em destaque;
/// - na formatação, a maneira escolhida no alto e uma linha por formatação do texto, com a prévia da escolhida.
///
/// Embaixo, quando há um colar em andamento, feito ou falho, a linha de estado. Sem nada para colar, uma frase diz por
/// quê.
///
/// Só desenha: o teclado (↑/↓, Tab, Return, ⌘V) é do contêiner da vitrine, e quem lê a área de transferência é o
/// modelo. O clique numa linha a escolhe e cola por `choose` ou `chooseFormat`, que precisam ler a área de transferência
/// de forma síncrona.
struct PasteSection: View {
    let model: MenuBarPanelModel
    /// Escolhe a maneira de colar do índice e cola.
    let choose: @MainActor (Int) -> Void
    /// Escolhe a formatação e cola.
    let chooseFormat: @MainActor (PasteTextFormat) -> Void
    /// Vai à etapa seguinte, como o Tab.
    let advance: @MainActor () -> Void
    /// Volta uma etapa, como o ⇧Tab.
    let retreat: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.options.isEmpty {
                // Abrindo o editor ou lendo a edição: a linha de estado, embaixo, já diz o que acontece.
                if !model.pasteStatus.isWorking {
                    Text(PasteDescription.emptyMessage(for: model.clipboard))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                }
            } else {
                switch model.stage {
                case .boards:
                    CopiedLine(kind: model.clipboardKind, content: model.clipboardContent, nextStage: "Colar", advance: advance)
                case .paste:
                    CopiedLine(
                        kind: model.clipboardKind, content: model.clipboardContent,
                        nextStage: model.stages.contains(.format) ? "Formatar" : nil, advance: advance)
                    PasteOptionRows(
                        options: model.options, selectedOption: model.selectedOption, clipboard: model.clipboardKind,
                        boardName: boardName, choose: choose)
                case .format:
                    ChosenOptionLine(
                        symbolName: chosenOption.map(PasteDescription.symbol(of:)) ?? "clipboard",
                        text: chosenOption.map {
                            PasteDescription.chosenOption($0, clipboard: model.clipboardKind, board: boardName)
                        } ?? "",
                        goBack: retreat)
                    FormatOptionRows(
                        formats: model.formats, selectedFormat: model.selectedFormat, preview: model.formattedText,
                        choose: chooseFormat)
                }
            }
            PasteStatusLine(status: model.pasteStatus)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PanelMetrics.contentPadding)
        .padding(.bottom, PanelMetrics.contentSpacing)
        .focusable(false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menu-bar-paste-section")
    }

    private var boardName: String {
        model.selectedEntry?.manifest.name ?? ""
    }

    private var chosenOption: PasteOption? {
        model.options.indices.contains(model.selectedOption) ? model.options[model.selectedOption] : nil
    }
}
