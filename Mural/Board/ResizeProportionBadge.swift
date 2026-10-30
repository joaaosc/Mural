import MuralKit
import SwiftUI

/// Etiqueta com a proporção em que o arrasto do canto de uma foto encaixou ("4:3", "Foto inteira"). Fica logo depois do canto
/// arrastado, para fora da foto, enquanto o encaixe dura e some quando o canto volta a andar livre.
struct ResizeProportionBadge: View {
    let proportion: ImageProportion

    /// Distância, em pontos de tela, entre o canto da foto e a etiqueta.
    nonisolated static let gap: CGFloat = 6

    var body: some View {
        Text(proportion.badgeTitle)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .glassEffect(.regular, in: .capsule)
            .fixedSize()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Durante o arrasto do canto de uma foto, mostra a proporção em que o tamanho encaixou e dá um toque no trackpad a cada
    /// encaixe novo. Num trackpad Force Touch o toque é sentido no dedo que arrasta (`.levelChange` só toca no macOS); num mouse,
    /// fica só a etiqueta. A etiqueta fica fora da foto, junto do canto arrastado, e tem o mesmo tamanho na tela em qualquer
    /// zoom, como a alça.
    func resizeProportionFeedback(_ proportion: ImageProportion?, corner: ResizeCorner, zoom: CGFloat) -> some View {
        overlay(alignment: corner.alignment) {
            ZStack {
                if let proportion {
                    ResizeProportionBadge(proportion: proportion)
                        .scaleEffect(
                            1 / zoom, anchor: UnitPoint(x: corner.isLeading ? 0 : 1, y: corner.isTop ? 1 : 0)
                        )
                        .transition(.opacity)
                }
            }
            .alignmentGuide(corner.isTop ? .top : .bottom) { dimensions in
                let gap = ResizeProportionBadge.gap / zoom
                return corner.isTop ? dimensions[.bottom] + gap : dimensions[.top] - gap
            }
            .animation(.easeOut(duration: 0.12), value: proportion)
        }
        .onChange(of: proportion) { old, new in
            if new != nil, new != old { HapticFeedback.play() }
        }
    }
}

#Preview("Etiqueta da proporção", traits: .fixedLayout(width: 320, height: 220)) {
    HStack(spacing: 40) {
        Theme.sticky(.blue)
            .frame(width: 120, height: 90)
            .resizeProportionFeedback(.fixed(width: 4, height: 3), corner: .bottomTrailing, zoom: 1)
        Theme.sticky(.green)
            .frame(width: 90, height: 120)
            .resizeProportionFeedback(.original, corner: .topLeading, zoom: 1)
    }
    .padding(40)
    .background(Theme.canvas)
}
