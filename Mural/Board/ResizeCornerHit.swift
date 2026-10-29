import CoreGraphics
import MuralKit
import SwiftUI

/// Qual canto de um elemento do mural uma posição alcança para redimensionar. A conta é a mesma para o ponto em que o arrasto
/// começa e para o ponto sob o ponteiro (que decide o cursor), por isso mora num lugar só.
enum ResizeCornerHit {
    /// O elemento precisa ter pelo menos 4 vezes o quadrado do canto, em pontos de tela, para aceitar os quatro cantos: com
    /// menos que isso os quadrados ocupariam quase toda a borda e sobraria pouco onde pegar e mover.
    private static let minimumSideInCorners: CGFloat = 4

    /// O canto cujo quadrado contém o ponto.
    /// - Parameters:
    ///   - point: o ponto, em pontos do mural, relativo ao canto de cima, à esquerda, do elemento.
    ///   - size: o tamanho do elemento, em pontos do mural.
    ///   - zoom: o zoom do mural. O quadrado tem `ResizeHandle.cornerSide` pontos de tela, ou seja, `cornerSide / zoom` pontos do mural.
    /// - Returns: `nil` fora dos quadrados. Num elemento pequeno na tela só existe o canto de baixo à direita (o da alça), e o
    ///   quadrado dele não passa de metade do menor lado.
    static func corner(at point: CGPoint, size: CGSize, zoom: CGFloat) -> ResizeCorner? {
        guard zoom > 0, size.width > 0, size.height > 0 else { return nil }
        let shortest = min(size.width, size.height)
        let side = ResizeHandle.cornerSide / zoom
        let allCorners = shortest * zoom >= minimumSideInCorners * ResizeHandle.cornerSide
        let reach = allCorners ? side : min(side, shortest / 2)
        guard point.x >= 0, point.x <= size.width, point.y >= 0, point.y <= size.height else { return nil }
        let nearLeading = point.x <= reach
        let nearTrailing = point.x >= size.width - reach
        let nearTop = point.y <= reach
        let nearBottom = point.y >= size.height - reach
        switch (nearTop, nearBottom, nearLeading, nearTrailing) {
        case (_, true, _, true): return .bottomTrailing
        case (true, _, true, _) where allCorners: return .topLeading
        case (true, _, _, true) where allCorners: return .topTrailing
        case (_, true, true, _) where allCorners: return .bottomLeading
        default: return nil
        }
    }
}

extension ResizeCorner {
    /// O cursor de redimensionar do canto.
    var pointerPosition: FrameResizePosition {
        switch self {
        case .topLeading: .topLeading
        case .topTrailing: .topTrailing
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        }
    }

    /// O canto como alinhamento de uma sobreposição.
    var alignment: Alignment {
        switch self {
        case .topLeading: .topLeading
        case .topTrailing: .topTrailing
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        }
    }
}
