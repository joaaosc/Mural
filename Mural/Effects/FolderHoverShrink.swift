import SwiftUI

/// Encolhe o cartão arrastado até um tamanho mínimo, em direção ao ponteiro, enquanto ele está
/// sobre uma pasta: assim a pasta continua visível por baixo. Na transição, um shader Metal
/// (`muralFolderHoverPinch`) "suga" a imagem para o ponteiro. Com Reduzir Movimento, só a escala.
///
/// `progress` 0 é o tamanho normal e 1, o mínimo. Parado em qualquer das pontas, nada é filtrado.
@Animatable
struct FolderHoverShrink: ViewModifier {
    var progress: Double
    /// Ponteiro no quadro do cartão, em pontos (pode cair fora de 0...largura e 0...altura).
    @AnimatableIgnored var anchor: CGPoint
    /// Escala no fim da transição; 1 quando o cartão já é pequeno e não precisa encolher.
    @AnimatableIgnored var minScale: CGFloat
    @AnimatableIgnored var reduceMotion: Bool

    /// Lado maior do cartão encolhido, em pontos.
    static let minimumLongestSide: CGFloat = 72
    /// Quanto a distorção pode deslocar a amostra, em fração da distância até a âncora.
    private static let pinch: CGFloat = 0.35

    /// Escala que deixa o lado maior do cartão em `minimumLongestSide`; 1 se ele já for menor.
    static func minScale(for size: CGSize) -> CGFloat {
        let longest = max(size.width, size.height)
        guard longest > minimumLongestSide else { return 1 }
        return minimumLongestSide / longest
    }

    func body(content: Content) -> some View {
        Group {
            if !reduceMotion && minScale < 1 && progress > 0 && progress < 1 {
                content.visualEffect { [progress, anchor, pinch = Self.pinch] content, proxy in
                    let size = proxy.size
                    let reachX = max(abs(anchor.x), abs(size.width - anchor.x)) * pinch
                    let reachY = max(abs(anchor.y), abs(size.height - anchor.y)) * pinch
                    return content.distortionEffect(
                        ShaderLibrary.default.muralFolderHoverPinch(.float2(size), .float2(anchor), .float(progress)),
                        maxSampleOffset: CGSize(width: reachX, height: reachY))
                }
            } else {
                // Fora da distorção, não envolve as camadas nativas de vídeo em um filtro Metal.
                content
            }
        }
        .visualEffect { [progress, anchor, minScale] content, proxy in
            let size = proxy.size
            let unit = UnitPoint(
                x: size.width > 0 ? anchor.x / size.width : 0.5,
                y: size.height > 0 ? anchor.y / size.height : 0.5)
            return content.scaleEffect(1 - progress * (1 - minScale), anchor: unit)
        }
    }
}

#Preview("Encolher sobre a pasta") {
    @Previewable @State var isShrunk = false

    VStack(spacing: 20) {
        RoundedRectangle(cornerRadius: Theme.mediaCorner)
            .fill(.orange.gradient)
            .frame(width: 150, height: 190)
            .modifier(
                FolderHoverShrink(
                    progress: isShrunk ? 1 : 0,
                    anchor: CGPoint(x: 75, y: 95),
                    minScale: FolderHoverShrink.minScale(for: CGSize(width: 150, height: 190)),
                    reduceMotion: false)
            )
            .animation(.smooth(duration: 0.5), value: isShrunk)

        Button(isShrunk ? "Crescer" : "Encolher") { isShrunk.toggle() }
    }
    .padding(40)
    .background(Theme.canvas)
}
