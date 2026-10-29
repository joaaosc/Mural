import Foundation
import MuralKit

/// Post-it, foto ou texto livre sendo redimensionado e o quadro (posição e tamanho) que o arrasto dá a ele agora, em pontos do mural.
struct ResizeDrag: Equatable {
    /// O elemento do mural que tem alça de redimensionar.
    enum Target: Equatable {
        case item(UUID)
        case freeText(UUID)

        var itemID: UUID? {
            guard case .item(let id) = self else { return nil }
            return id
        }

        var freeTextID: UUID? {
            guard case .freeText(let id) = self else { return nil }
            return id
        }
    }

    var target: Target
    /// O canto que a pessoa arrasta; o oposto fica parado.
    var corner: ResizeCorner
    /// Posição ao vivo do canto de cima, à esquerda. Muda quando o canto arrastado é o da esquerda ou o de cima
    /// (`BoardLayout.resizedFrame`); nos outros é a posição gravada.
    var origin: BoardPoint
    /// Tamanho ao vivo, já preso aos limites e em pontos inteiros (`BoardLayout.resizedFrame`).
    var size: BoardSize
    /// Se Shift estava pressionado no último movimento: o tamanho mantém a proporção do tamanho de partida. Guardado para o
    /// valor gravado ao soltar ser o mesmo que a pessoa estava vendo, mesmo que ela solte o Shift um instante antes do botão.
    var keepsProportion: Bool
    /// Numa foto, a proporção em que o tamanho encaixou agora (`BoardLayout.resizedImageSize`); `nil` fora de um encaixe.
    var proportion: ImageProportion? = nil
}
