import MuralKit
import SwiftUI

/// O cartão embutido na miniatura da nota: uma linha com o símbolo do tipo e o título, no tom do texto do papel
/// (`StretchMarkdownStyle.paperCard`). O cartão inteiro só aparece na página de leitura.
struct EmbeddedCardCompactRow: View {
    let card: EmbeddedCard
    let title: String

    var body: some View {
        Label(title, systemImage: card.itemKind.creationSymbol)
            .font(.system(size: 5.5))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
