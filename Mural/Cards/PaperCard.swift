import MuralKit
import StretchText
import StretchTextUI
import SwiftUI

/// Nota de texto em miniatura: uma folha com título e o resumo do corpo, em que
/// cada parágrafo dobrado mostra só a frase curta.
///
/// As fontes são fixas de propósito: o cartão é uma miniatura da página,
/// não texto para leitura. O conteúdo legível fica na tela de detalhe.
struct PaperCard: View {
    let title: String
    /// O corpo dobrado; `nil` quando a nota não tem corpo.
    let summary: FoldResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(2)
            if let summary {
                StretchMarkdownView(result: summary, state: StretchState(document: summary.document))
                    .stretchMarkdownStyle(.paperCard)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .paperSheet()
    }
}

#Preview {
    HStack(spacing: 24) {
        PaperCard(
            title: "Design Philosophy",
            summary: NoteFolding.fold(
                "A design philosophy is a set of values that guides choices. Clarity before ornament. Light before furniture.",
                record: nil))
        PaperCard(
            title: "Visita",
            summary: NoteFolding.fold(
                """
                ## Segunda

                A visita é de manhã. Medir a parede norte. Levar as amostras de **tecido**.

                - [x] Pedir as luminárias
                - [ ] Revisar a planta
                """,
                record: nil))
    }
    .frame(width: 270, height: 150)
    .padding(40)
    .background(Theme.canvas)
}
