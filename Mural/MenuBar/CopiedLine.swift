import MuralKit
import SwiftUI

/// "Copiado: Texto · Comprar pão": o tipo do que está copiado e, quando o conteúdo já foi lido, uma prévia curta.
///
/// Com uma etapa seguinte, a linha termina na dica do Tab e o clique nela faz o mesmo que o Tab. Sem etapa seguinte, é
/// só texto.
struct CopiedLine: View {
    let kind: ClipboardKind
    let content: ClipboardContent?
    /// O nome curto da etapa que o Tab mostra ("Colar", "Formatar"); `nil` quando não há o que mostrar a mais.
    let nextStage: String?
    /// Vai à etapa seguinte.
    let advance: @MainActor () -> Void
    /// O texto foi mudado no editor do painel: o rótulo diz "Editado:" em vez de "Copiado:".
    var isEdited = false

    var body: some View {
        if let nextStage {
            Button(action: advance) {
                line(nextStage: nextStage)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Tab: \(nextStage)")
            .accessibilityHint(nextStage == "Colar" ? "Mostra as maneiras de colar." : "Mostra como formatar o texto.")
            .accessibilityIdentifier("menu-bar-copied-line")
        } else {
            line(nextStage: nil)
                .accessibilityIdentifier("menu-bar-copied-line")
        }
    }

    private func line(nextStage: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: PasteDescription.symbol(for: kind))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(PasteDescription.copiedLabel(isEdited: isEdited))
                .foregroundStyle(.secondary)
            Text(PasteDescription.name(for: kind))
                .fontWeight(.medium)
            if let preview = PasteDescription.preview(of: content) {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(preview)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 12)
            if let nextStage {
                KeyHint(symbol: "arrow.right.to.line", label: nextStage, description: "Tab: \(nextStage)")
            }
        }
        .font(.subheadline)
        // O mesmo recuo do conteúdo das linhas de opção, para o símbolo ficar na mesma coluna.
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Copiado e editado", traits: .fixedLayout(width: PanelMetrics.panelWidth, height: 90)) {
    VStack(alignment: .leading) {
        CopiedLine(kind: .text("Comprar pão"), content: .pasted(.text("Comprar pão")), nextStage: "Colar", advance: {})
        CopiedLine(
            kind: .text("Comprar pão (editado)"), content: .pasted(.text("Comprar pão (editado)")), nextStage: "Colar",
            advance: {}, isEdited: true)
    }
    .padding()
}
