import MuralKit
import SwiftUI

/// Uma linha por formatação do texto copiado; a escolhida leva o destaque, a prévia do resultado e a dica do Return.
///
/// A prévia é a primeira linha do texto já formatado. Antes de o texto ser lido (o macOS só deixa ler num colar pedido
/// pela pessoa), ela avisa que a formatação vale para o que o colar ler.
struct FormatOptionRows: View {
    let formats: [PasteTextFormat]
    let selectedFormat: PasteTextFormat
    /// O texto com a formatação; `nil` enquanto o texto não foi lido.
    let preview: @MainActor (PasteTextFormat) -> String?
    /// Escolhe a formatação e cola.
    let choose: @MainActor (PasteTextFormat) -> Void

    @Namespace private var selectionPill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 2) {
            ForEach(formats) { format in
                let isSelected = format == selectedFormat
                let title = PasteDescription.title(of: format)
                // Só a escolhida calcula a prévia: as outras não a mostram.
                let summary = isSelected ? PasteDescription.formatPreview(of: preview(format)) : ""
                HStack(spacing: 6) {
                    PanelActionRow(
                        symbolName: PasteDescription.symbol(of: format),
                        title: title,
                        summary: summary,
                        isSelected: isSelected,
                        namespace: selectionPill,
                        help: "Colar com a formatação \(title)",
                        accessibilityLabel: "Formatar: \(title)",
                        accessibilityHint: "Cola o texto com esta formatação no mural do centro da vitrine.",
                        action: { choose(format) }
                    )
                    .focusable(false)
                    .accessibilityValue(summary)
                    .accessibilityIdentifier("menu-bar-format-\(format.rawValue)")

                    KeyHint(symbol: "return", label: "Colar", description: "Return cola o texto formatado", isCompact: true)
                        .opacity(isSelected ? 1 : 0)
                        .accessibilityHidden(!isSelected)
                }
            }
        }
        .animation(PanelMotion.animation(PanelMotion.selection, reduceMotion: reduceMotion), value: selectedFormat)
    }
}
