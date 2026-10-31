import SwiftUI

/// Encolhe o cartão arrastado até um tamanho mínimo, em direção ao ponteiro, enquanto ele está
/// sobre uma pasta: assim a pasta continua visível por baixo. Na transição, um shader Metal
/// (`muralFolderHoverPinch`) "suga" a imagem para o ponteiro. Com Reduzir Movimento, só a escala.
///
/// `progress` 0 é o tamanho normal e 1, o mínimo. Parado em qualquer das pontas, nada é filtrado.
///
/// A view fica sempre no mesmo ramo durante o arrasto: trocar de ramo (um `if` que entra e sai do filtro) recria o
/// cartão no meio do gesto, o arrasto é cancelado e o cartão volta ao lugar ao chegar na pasta. Por isso o filtro é
/// ligado e desligado por `isEnabled`, e só `allowsDistortion` (fixo por cartão) decide se ele existe.
@Animatable
struct FolderHoverShrink: ViewModifier {
    var progress: Double
    /// Ponteiro no quadro do cartão, em pontos (pode cair fora de 0...largura e 0...altura).
    @AnimatableIgnored var anchor: CGPoint
    /// Escala no fim da transição; 1 quando o cartão já é pequeno e não precisa encolher.
    @AnimatableIgnored var minScale: CGFloat
    @AnimatableIgnored var reduceMotion: Bool
    /// Se o cartão pode passar pelo shader. Falso nos cartões de vídeo: o filtro Metal envolveria a camada nativa do
    /// player e a prévia ao passar o ponteiro deixaria de aparecer. Não muda durante um arrasto.
    @AnimatableIgnored var allowsDistortion = true

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
        // Os dois ramos dependem só de valores fixos durante o gesto (`allowsDistortion`, Reduzir Movimento).
        if allowsDistortion && !reduceMotion {
            content.visualEffect { [progress, anchor, minScale, pinch = Self.pinch] content, proxy in
                let size = proxy.size
                // Distância da âncora ao canto mais longe: limita o quanto a amostra se desloca.
                let reachX = max(abs(anchor.x), abs(size.width - anchor.x)) * pinch
                let reachY = max(abs(anchor.y), abs(size.height - anchor.y)) * pinch
                return
                    content
                    .distortionEffect(
                        ShaderLibrary.default.muralFolderHoverPinch(.float2(size), .float2(anchor), .float(progress)),
                        maxSampleOffset: CGSize(width: reachX, height: reachY),
                        isEnabled: minScale < 1 && progress > 0 && progress < 1
                    )
                    .scaleEffect(1 - progress * (1 - minScale), anchor: Self.unit(anchor, in: size))
            }
        } else {
            content.visualEffect { [progress, anchor, minScale] content, proxy in
                content.scaleEffect(1 - progress * (1 - minScale), anchor: Self.unit(anchor, in: proxy.size))
            }
        }
    }

    /// A âncora como fração do quadro do cartão. Chamado de dentro do `visualEffect`, fora do main actor.
    private nonisolated static func unit(_ anchor: CGPoint, in size: CGSize) -> UnitPoint {
        UnitPoint(
            x: size.width > 0 ? anchor.x / size.width : 0.5,
            y: size.height > 0 ? anchor.y / size.height : 0.5)
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
