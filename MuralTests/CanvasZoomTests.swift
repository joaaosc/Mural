import CoreGraphics
import Testing

@testable import Mural

@Suite("Zoom do mural")
struct CanvasZoomTests {
    @Test("Dentro dos limites, a pinça é direta")
    func insideRangeIsDirect() {
        #expect(CanvasZoom.rubberBanded(1.3) == 1.3)
        #expect(CanvasZoom.rubberBanded(CanvasZoom.range.upperBound) == CanvasZoom.range.upperBound)
    }

    @Test("Fora dos limites, a pinça resiste em vez de travar ou disparar")
    func outsideRangeResists() {
        let upper = CanvasZoom.range.upperBound
        let beyond = CanvasZoom.rubberBanded(upper * 2)
        #expect(beyond > upper, "ainda cede um pouco")
        #expect(beyond < upper * 1.25, "mas bem menos que o gesto")
        #expect(CanvasZoom.rubberBanded(upper * 3) > beyond, "continua crescendo devagar")
        let lower = CanvasZoom.range.lowerBound
        let below = CanvasZoom.rubberBanded(lower / 2)
        #expect(below < lower && below > lower * 0.8)
    }

    @Test("Ao assentar, o zoom fica dentro dos limites")
    func clamping() {
        #expect(CanvasZoom.clamped(10) == CanvasZoom.range.upperBound)
        #expect(CanvasZoom.clamped(0.01) == CanvasZoom.range.lowerBound)
        #expect(CanvasZoom.clamped(1) == 1)
    }

    @Test("O ponto sob a pinça continua no mesmo lugar da tela", arguments: [0.5, 1.6, 2.0])
    func anchorStaysPut(scale: CGFloat) {
        let zoom: CGFloat = 1.2
        let offset = CGPoint(x: 140, y: 60)
        let pointer = CGPoint(x: 300, y: 220)  // posição na janela
        let anchor = CGPoint(x: offset.x + pointer.x, y: offset.y + pointer.y)
        let newOffset = CanvasZoom.offset(keeping: anchor, from: offset, scale: scale)

        // Ponto do mural (sem zoom) que estava sob o ponteiro, antes e depois.
        let before = CGPoint(x: (offset.x + pointer.x) / zoom, y: (offset.y + pointer.y) / zoom)
        let after = CGPoint(x: (newOffset.x + pointer.x) / (zoom * scale), y: (newOffset.y + pointer.y) / (zoom * scale))
        #expect(abs(before.x - after.x) < 0.001 && abs(before.y - after.y) < 0.001)
    }

    @Test("Ajustar à janela faz caber os cartões, sem passar dos limites")
    func fitting() {
        let fit = CanvasZoom.fitting(extent: CGSize(width: 1920, height: 920), in: CGSize(width: 1000, height: 800))
        #expect(fit == 0.5)
        #expect(
            CanvasZoom.fitting(extent: CGSize(width: 10, height: 10), in: CGSize(width: 1000, height: 800)) == CanvasZoom.range.upperBound)
        #expect(CanvasZoom.fitting(extent: .zero, in: .zero) == 1)
    }
}
