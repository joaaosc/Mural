import CoreGraphics
import Foundation

/// Seleção por retângulo: Shift + arrastar desenha o retângulo; os cartões que ele cruza somam-se
/// ao que já estava marcado, como no Finder.
nonisolated struct MarqueeSelection: Equatable, Sendable {
    var start: CGPoint
    var current: CGPoint
    /// O que já estava marcado quando o arrasto começou.
    let base: Set<UUID>

    init(start: CGPoint, base: Set<UUID>) {
        self.start = start
        self.current = start
        self.base = base
    }

    /// Retângulo normalizado: vale arrastando em qualquer direção.
    var rect: CGRect {
        CGRect(
            x: min(start.x, current.x), y: min(start.y, current.y),
            width: abs(current.x - start.x), height: abs(current.y - start.y))
    }

    /// Cartões cujos quadros cruzam o retângulo. Largura ou altura zero não marca nada.
    func hits(in frames: [UUID: CGRect]) -> Set<UUID> {
        let rect = rect
        guard rect.width > 0, rect.height > 0 else { return [] }
        var result: Set<UUID> = []
        for (id, frame) in frames where frame.intersects(rect) {
            result.insert(id)
        }
        return result
    }

    /// O que fica marcado: a base mais os cartões cruzados.
    func selection(in frames: [UUID: CGRect]) -> Set<UUID> {
        base.union(hits(in: frames))
    }
}
