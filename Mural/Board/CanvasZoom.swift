import CoreGraphics
import Foundation

/// Matemática do zoom do mural, separada da view para poder ser testada.
nonisolated enum CanvasZoom {
    static let range: ClosedRange<CGFloat> = 0.4...2.5
    /// Passo de Aproximar e Afastar (⌘= e ⌘−).
    static let step: CGFloat = 1.25
    /// Quanto o zoom ainda cede além dos limites durante a pinça (0 = trava, 1 = livre).
    static let resistance: CGFloat = 0.25

    static func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// Zoom durante a pinça: livre dentro dos limites; fora deles, resiste como um
    /// elástico em vez de parar seco. Ao soltar, assenta no limite.
    static func rubberBanded(_ value: CGFloat) -> CGFloat {
        if value > range.upperBound {
            return range.upperBound * pow(value / range.upperBound, resistance)
        }
        if value < range.lowerBound {
            return range.lowerBound * pow(value / range.lowerBound, resistance)
        }
        return value
    }

    /// Rolagem que mantém parado na tela o ponto `anchor` quando o zoom é multiplicado
    /// por `scale`. `anchor` está em coordenadas do conteúdo ampliado (rolagem + posição
    /// na janela); o conteúdo cresce a partir do canto superior esquerdo.
    static func offset(keeping anchor: CGPoint, from offset: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: offset.x + anchor.x * (scale - 1), y: offset.y + anchor.y * (scale - 1))
    }

    /// Zoom que faz caber na janela a área ocupada pelos cartões, com uma margem.
    static func fitting(extent: CGSize, in viewport: CGSize, margin: CGFloat = 80) -> CGFloat {
        guard viewport.width > 0, viewport.height > 0 else { return 1 }
        let width = max(extent.width + margin, 1)
        let height = max(extent.height + margin, 1)
        return clamped(min(viewport.width / width, viewport.height / height))
    }
}
