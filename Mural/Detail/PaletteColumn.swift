import MuralKit
import SwiftUI

/// Coluna de bolinhas com as cores dominantes da imagem.
struct PaletteColumn: View {
    let colors: [PaletteColor]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(color.color)
                    .overlay(Circle().strokeBorder(.black.opacity(0.08)))
                    .frame(width: 22, height: 22)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Paleta com \(colors.count) cores")
    }
}
