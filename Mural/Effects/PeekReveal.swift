import SwiftUI

/// Entrada da prévia de pasta: os cartões surgem a partir da borda da pasta, com uma
/// borda suave que corre da esquerda para a direita (shader Metal `muralPeekReveal`).
///
/// O filtro só existe durante a entrada; com a prévia parada, nada é filtrado.
struct PeekReveal: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(PeekRevealEffect(progress: phase.isIdentity ? 1 : 0))
    }
}

/// Máscara animável da revelação: 0 esconde tudo e 1 mostra tudo.
@Animatable
struct PeekRevealEffect: ViewModifier {
    var progress: Double

    /// Largura da borda suave, em pontos.
    private static let feather: Float = 64
    /// Folga em volta da prévia para o filtro não cortar as sombras dos cartões.
    private static let bleed: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(Self.bleed)
            .visualEffect { [progress, feather = Self.feather] content, proxy in
                content.colorEffect(
                    ShaderLibrary.default.muralPeekReveal(
                        .float(Float(proxy.size.width)),
                        .float(feather),
                        .float(Float(progress))
                    ),
                    isEnabled: progress < 1
                )
            }
            .padding(-Self.bleed)
    }
}

#Preview("Revelação da prévia") {
    @Previewable @State var isShown = false

    VStack(alignment: .leading, spacing: 20) {
        ZStack(alignment: .leading) {
            if isShown {
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Theme.mediaCorner)
                            .fill(.orange.gradient)
                            .frame(width: 96, height: 128)
                            .cardShadow()
                    }
                }
                .transition(PeekReveal())
            }
        }
        .frame(width: 330, height: 140, alignment: .leading)

        Button(isShown ? "Esconder" : "Mostrar") {
            withAnimation(.smooth(duration: 0.6)) { isShown.toggle() }
        }
    }
    .padding(40)
    .background(Theme.canvas)
}
