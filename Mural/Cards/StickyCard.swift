import MuralKit
import SwiftUI

/// Post-it: texto curto em fonte monoespaçada sobre papel colorido.
struct StickyCard: View {
    let text: String
    let color: StickyColor?

    var body: some View {
        Text(text)
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(Theme.stickyInk)
            .padding(10)
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
