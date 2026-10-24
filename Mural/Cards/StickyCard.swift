import MuralKit
import SwiftUI

/// Post-it: texto curto em fonte monoespaçada sobre papel colorido.
///
/// A letra e a margem crescem com o tamanho que a pessoa deu ao post-it no mural (`boardContentScale`); com escala 1, o
/// desenho é o de sempre, que é o das pastas e das prévias.
struct StickyCard: View {
    let text: String
    let color: StickyColor?

    @Environment(\.boardContentScale) private var contentScale

    var body: some View {
        Text(text)
            .font(.system(size: 8 * contentScale, design: .monospaced))
            .foregroundStyle(Theme.stickyInk)
            .padding(10 * contentScale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.sticky(color), in: .rect(cornerRadius: 3))
            .cardShadow()
    }
}

#Preview {
    HStack(spacing: 20) {
        StickyCard(text: "The idea is this: make every room feel like the garden is inside it.", color: .pink)
        StickyCard(text: "Don't forget: warm light only.", color: .orange)
    }
    .frame(width: 260, height: 110)
    .padding(40)
    .background(Theme.canvas)
}

#Preview("Com cor", traits: .fixedLayout(width: 360, height: 130)) {
    HStack(spacing: 20) {
        ForEach([TagColor.red, .blue, .green]) { color in
            StickyCard(text: "Só luz quente, nada acima de 3000K.", color: .yellow)
                .colorTagDot(color)
                .frame(width: 100, height: 90)
        }
    }
    .padding(24)
    .background(Theme.canvas)
}

#Preview("Tamanhos escolhidos", traits: .fixedLayout(width: 520, height: 280)) {
    HStack(alignment: .top, spacing: 20) {
        StickyCard(text: "Menor: 80 × 80, com a letra um pouco menor.", color: .yellow)
            .contentScaled(for: BoardItem(kind: .sticky, title: ""), width: 80, height: 80)
            .frame(width: 80, height: 80)
        StickyCard(text: "Padrão: 110 × 110.", color: .pink)
            .frame(width: 110, height: 110)
        StickyCard(text: "Muito grande: 220 × 220, com a letra e a margem no dobro.", color: .green)
            .contentScaled(for: BoardItem(kind: .sticky, title: ""), width: 220, height: 220)
            .frame(width: 220, height: 220)
    }
    .padding(24)
    .background(Theme.canvas)
}
