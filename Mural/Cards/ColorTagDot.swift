import MuralKit
import SwiftUI

/// Bolinha da cor da tag, no canto dos cartões que não têm papel para tingir (post-it, link e mídia).
/// A cor também vai no valor de acessibilidade do cartão (`CardButton`), então a bolinha fica escondida.
struct ColorTagDot: View {
    let color: TagColor

    var body: some View {
        Circle()
            .fill(color.color)
            .overlay { Circle().strokeBorder(.white, lineWidth: 1.5) }
            .frame(width: 10, height: 10)
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Bolinha da cor da tag no canto de cima, à direita, para os cartões que não têm papel para tingir.
    func colorTagDot(_ tag: TagColor?) -> some View {
        overlay(alignment: .topTrailing) {
            if let tag {
                ColorTagDot(color: tag).padding(6)
            }
        }
    }
}

#Preview("Sete cores", traits: .fixedLayout(width: 260, height: 120)) {
    VStack(spacing: 24) {
        HStack(spacing: 12) {
            ForEach(TagColor.allCases) { ColorTagDot(color: $0) }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.canvas)
        HStack(spacing: 12) {
            ForEach(TagColor.allCases) { ColorTagDot(color: $0) }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.12, green: 0.12, blue: 0.14))
    }
}
