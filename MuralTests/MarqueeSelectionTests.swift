import CoreGraphics
import Foundation
import Testing

@testable import Mural

/// Conta pura da seleção por retângulo (Shift + arrastar).
struct MarqueeSelectionTests {
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    private var frames: [UUID: CGRect] {
        [
            a: CGRect(x: 0, y: 0, width: 100, height: 100),
            b: CGRect(x: 200, y: 0, width: 100, height: 100),
            c: CGRect(x: 0, y: 200, width: 100, height: 100),
        ]
    }

    private func marquee(from start: CGPoint, to end: CGPoint, base: Set<UUID> = []) -> MarqueeSelection {
        var marquee = MarqueeSelection(start: start, base: base)
        marquee.current = end
        return marquee
    }

    @Test("Arrastar para cima e para a esquerda dá o mesmo retângulo")
    func normalizedRect() {
        let down = marquee(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 60, y: 90))
        let up = marquee(from: CGPoint(x: 60, y: 90), to: CGPoint(x: 10, y: 20))
        #expect(down.rect == CGRect(x: 10, y: 20, width: 50, height: 70))
        #expect(up.rect == down.rect)
    }

    @Test("Marca só os cartões que o retângulo toca")
    func hitsOnlyTouched() {
        let m = marquee(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 250, y: 80))
        #expect(m.hits(in: frames) == [a, b])
    }

    @Test("A seleção soma a base aos cartões cruzados")
    func unionWithBase() {
        let m = marquee(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 80, y: 80), base: [c])
        #expect(m.selection(in: frames) == [a, c])
    }

    @Test("Sem cruzar nada, fica só a base")
    func nothingCrossed() {
        let m = marquee(from: CGPoint(x: 120, y: 120), to: CGPoint(x: 180, y: 180), base: [b])
        #expect(m.hits(in: frames).isEmpty)
        #expect(m.selection(in: frames) == [b])
    }

    @Test("Retângulo sem área não marca nada")
    func degenerateRect() {
        let m = MarqueeSelection(start: CGPoint(x: 50, y: 50), base: [])
        #expect(m.hits(in: frames).isEmpty)
        #expect(m.selection(in: frames).isEmpty)
    }
}
