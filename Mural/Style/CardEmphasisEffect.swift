import SwiftUI

/// Mistura a cor de cada pixel, inclusive fora dos limites de layout, preservando seu alfa.
@Animatable
struct CardEmphasisEffect: ViewModifier {
    var emphasis: Double

    func body(content: Content) -> some View {
        Group {
            if emphasis < 1 {
                content.colorEffect(
                    ShaderLibrary.default.muralCardEmphasis(.color(Theme.canvas), .float(Float(emphasis))))
            } else {
                // Sem filtro no cartão em destaque: a camada nativa do vídeo precisa desenhar diretamente.
                content
            }
        }
        .environment(\.cardEmphasis, emphasis)
    }
}
