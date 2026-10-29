import Foundation
import MuralKit

/// Post-it, foto ou texto livre sendo redimensionado e o tamanho que o arrasto dá a ele agora, em pontos do mural.
struct ResizeDrag: Equatable {
    /// O elemento do mural que tem alça de redimensionar.
    enum Target: Equatable {
        case item(UUID)
        case freeText(UUID)

        var freeTextID: UUID? {
            guard case .freeText(let id) = self else { return nil }
            return id
        }
    }

    var target: Target
    /// Tamanho ao vivo, já preso aos limites e em pontos inteiros (`BoardLayout.resizedSize`).
    var size: BoardSize
    /// Se Shift estava pressionado no último movimento: o tamanho mantém a proporção do tamanho de partida. Guardado para o
    /// valor gravado ao soltar ser o mesmo que a pessoa estava vendo, mesmo que ela solte o Shift um instante antes do botão.
    var keepsProportion: Bool
    /// Numa foto, a proporção em que o tamanho encaixou agora (`BoardLayout.resizedImageSize`); `nil` fora de um encaixe.
    var proportion: ImageProportion? = nil
}
