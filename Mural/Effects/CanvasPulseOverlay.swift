import SwiftUI

/// Onda curta e decorativa de luz para a viewport do mural.
///
/// A trilha termina transparente, portanto não há animação em repouso. A
/// camada é separada do conteúdo: o shader nunca filtra cartões, texto ou
/// miniaturas, e o overlay não recebe entrada.
struct CanvasPulseOverlay: View {
    let trigger: Int
    let isEnabled: Bool

    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .keyframeAnimator(initialValue: 1.0, trigger: trigger) { content, progress in
                content.visualEffect { content, geometry in
                    content.colorEffect(
                        ShaderLibrary.default.muralCanvasPulse(
                            .float2(Float(geometry.size.width), Float(geometry.size.height)),
                            .float(progress)
                        ),
                        isEnabled: isEnabled && progress > 0 && progress < 1
                    )
                    .opacity(isEnabled && progress > 0 && progress < 1 ? 1 : 0)
                }
            } keyframes: { _ in
                KeyframeTrack(\.self) {
                    MoveKeyframe(0.0)
                    LinearKeyframe(1.0, duration: 0.82)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#Preview("Canvas pulse") {
    @Previewable @State var trigger = 0

    VStack(spacing: 12) {
        CanvasPulseOverlay(trigger: trigger, isEnabled: true)
            .frame(width: 640, height: 360)
            .background(.gray)

        Button("Disparar onda") { trigger += 1 }
    }
}

#Preview("Canvas pulse — desativado") {
    CanvasPulseOverlay(trigger: 1, isEnabled: false)
        .frame(width: 640, height: 360)
        .background(.gray)
}
