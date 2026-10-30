import MuralKit
import SwiftUI

/// A seção do painel entre a vitrine e o rodapé, que muda com a etapa do teclado (``PanelStage``):
/// - na vitrine, só a linha "Copiado", com a dica do Tab (nenhuma maneira de colar fica escolhida) ou, sem nada que dê para
///   colar (privado ou negado pelo sistema), a frase que diz por quê. Sem nada copiado, "Nada copiado" com a dica do Tab: a
///   opção de abrir o editor está nas maneiras de colar;
/// - nas maneiras de colar, a linha "Copiado" e uma linha por maneira, com a escolhida em destaque; a última, sempre, abre o
///   editor de texto.
///
/// Embaixo, quando há um colar em andamento, feito ou falho, a linha de estado.
///
/// Só desenha: o teclado (↑/↓, Tab, Return, ⌘V) é do contêiner da vitrine, e quem lê a área de transferência é o
/// modelo. O clique numa linha a escolhe e cola por `choose`, que precisa ler a área de transferência de forma síncrona.
struct PasteSection: View {
    @Bindable var model: MenuBarPanelModel
    /// Escolhe a maneira de colar do índice e cola.
    let choose: @MainActor (Int) -> Void
    /// Vai à etapa seguinte, como o Tab.
    let advance: @MainActor () -> Void
    /// Volta uma etapa, como o ⇧Tab.
    let retreat: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !model.hasPasteOptions && model.stage == .boards && model.clipboard != .nothing {
                Text(PasteDescription.emptyMessage(for: model.clipboard))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
            } else {
                switch model.stage {
                case .boards:
                    CopiedLine(
                        kind: model.clipboardKind, content: model.clipboardContent, nextStage: "Colar", advance: advance)
                case .paste:
                    CopiedLine(kind: model.clipboardKind, content: model.clipboardContent, nextStage: nil, advance: advance)
                    PasteOptionRows(
                        options: model.options, selectedOption: model.selectedOption, clipboard: model.clipboardKind,
                        boardName: boardName, choose: choose)
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
}
