import SwiftUI

/// Nota de texto em miniatura: uma folha com título e corpo bem pequeno.
///
/// As fontes são fixas de propósito: o cartão é uma miniatura da página,
/// não texto para leitura. O conteúdo legível fica na tela de detalhe.
struct PaperCard: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(2)
            Text(text)
                .font(.system(size: 5.5))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .paperSheet()
    }
}

#Preview {
    PaperCard(title: "Design Philosophy", text: "Clarity before ornament. Light before furniture. Every object earns its place.")
        .frame(width: 120, height: 150)
        .padding(40)
        .background(Theme.canvas)
}
