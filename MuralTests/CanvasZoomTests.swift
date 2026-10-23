import CoreGraphics
import MuralKit
import Testing

@testable import Mural

@Suite("Zoom do mural")
struct CanvasZoomTests {
    @Test("Um assentamento antigo não pode publicar depois de uma nova interação")
    @MainActor
    func staleSettleIsIgnored() {
        var completions: [() -> Void] = []
        let controller = CanvasZoomController { changes, completion in
            changes()
            completions.append(completion)
        }
        controller.scrollOffset = CGPoint(x: 120, y: 80)
        controller.viewport = CGSize(width: 800, height: 600)

        // O primeiro assentamento chega ao limite superior e fica pendente.
        controller.pinchChanged(magnification: 4, startLocation: CGPoint(x: 240, y: 180))
        controller.pinchEnded(magnification: 4)
        // O comando rápido deve partir do alvo pendente, já no limite, e não
        // programar uma multiplicação posterior do zoom antigo.
        controller.zoomIn()

        #expect(completions.count == 2)
        completions[0]()
        #expect(controller.zoom == 1)

        completions[1]()
        #expect(controller.zoom == CanvasZoom.range.upperBound)
        #expect(controller.liveScale == 1)
    }

    @Test("Ajustar à janela invalida um assentamento pendente")
    @MainActor
    func fitInvalidatesPendingSettle() {
        var completions: [() -> Void] = []
        let controller = CanvasZoomController { changes, completion in
            changes()
            completions.append(completion)
        }
        controller.pinchChanged(magnification: 4, startLocation: .zero)
        controller.pinchEnded(magnification: 4)

        controller.contentExtent = CGSize(width: 1920, height: 920)
        controller.viewport = CGSize(width: 1000, height: 800)
        controller.fitToWindow()
        #expect(controller.zoom == 0.5)

        completions[0]()
        #expect(controller.zoom == 0.5)
        #expect(controller.liveScale == 1)
    }

    @Test("Ajustar à janela publica o estado confirmado")
    @MainActor
    func fitPublishesWorkspace() {
        var published: CanvasWorkspaceState?
        let controller = CanvasZoomController { changes, completion in
            changes()
            completion()
        }
        controller.onWorkspaceChange = { published = $0 }
        controller.contentExtent = CGSize(width: 1920, height: 920)
        controller.viewport = CGSize(width: 1000, height: 800)
        controller.scrollOffset = CGPoint(x: 200, y: 100)

        controller.fitToWindow()

        #expect(published?.confirmedZoom == 0.5)
        #expect(published?.logicalCenter == BoardPoint(x: 1_000, y: 800))
    }

    @Test("Comandos de zoom usam o centro real do retângulo visível")
    @MainActor
    func zoomCommandUsesVisibleRectCenter() {
        let controller = CanvasZoomController { changes, completion in
            changes()
            completion()
        }
        controller.apply(
            CanvasScrollMetrics(
                contentOffset: CGPoint(x: 200, y: 100),
                containerSize: CGSize(width: 800, height: 600),
                contentSize: CGSize(width: 3_000, height: 2_000),
                visibleRect: CGRect(x: 200, y: 100, width: 600, height: 400)))

        controller.zoomIn()

        #expect(controller.zoom == 1.25)
        #expect(controller.scrollRequest?.point == CGPoint(x: 325, y: 175))
    }

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

    @Test("Preparar saída persiste o alvo aceito, nunca a escala visual")
    @MainActor
    func prepareToLeaveConsolidatesTarget() {
        var completions: [() -> Void] = []
        let controller = CanvasZoomController { changes, completion in
            changes()
            completions.append(completion)
        }
        controller.viewport = CGSize(width: 800, height: 600)
        controller.scrollOffset = CGPoint(x: 120, y: 80)
        controller.pinchChanged(magnification: 1.5, startLocation: CGPoint(x: 240, y: 180))
        controller.pinchEnded(magnification: 1.5)

        let state = controller.prepareToLeave()

        #expect(controller.liveScale == 1)
        #expect(state.confirmedZoom == Double(controller.zoom))
        #expect(state.confirmedZoom > 1)
        completions[0]()
        #expect(controller.zoom == CGFloat(state.confirmedZoom))
    }
}
