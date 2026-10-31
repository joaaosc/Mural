import CoreGraphics
import Testing

@testable import Mural

@Suite("Lugar do Tocando agora")
@MainActor
struct NowPlayingPlacementTests {
    private let container = CGSize(width: 1000, height: 600)

    @Test("Sem nada embaixo, fica centralizado na margem de baixo")
    func nothingBelow() {
        let placement = NowPlayingPlacement(container: container, obstacles: [])
        #expect(placement.originX == 360)  // (1000 - 280) / 2
        #expect(placement.maxWidth == 280)
        #expect(placement.bottomPadding == 18)
    }

    @Test("Sobe acima da barra centralizada")
    func liftsAboveCenteredBar() {
        let bar = CGRect(x: 380, y: 520, width: 240, height: 48)
        let placement = NowPlayingPlacement(container: container, obstacles: [bar])
        #expect(placement.originX == 360)
        #expect(placement.bottomPadding == 90)  // 600 - 520 + 10
    }

    @Test("Controles que não cruzam o centro não a fazem subir")
    func ignoresControlsOutsideItsStrip() {
        let zoom = CGRect(x: 880, y: 530, width: 100, height: 40)
        let placement = NowPlayingPlacement(container: container, obstacles: [zoom])
        #expect(placement.bottomPadding == 18)
    }

    @Test("Um controle que encosta na faixa, dentro do vão, conta")
    func controlWithinGapCounts() {
        // A faixa da cápsula vai de 360 a 640; com o vão de 12, qualquer coisa que comece antes de 652 cruza.
        let close = CGRect(x: 645, y: 530, width: 100, height: 40)
        let placement = NowPlayingPlacement(container: container, obstacles: [close])
        #expect(placement.bottomPadding == 80)  // 600 - 530 + 10
    }

    @Test("Sobe acima do mais alto dos controles que cruzam")
    func liftsAboveTheHighestCrossing() {
        let low = CGRect(x: 400, y: 540, width: 100, height: 40)
        let high = CGRect(x: 550, y: 500, width: 80, height: 60)
        let placement = NowPlayingPlacement(container: container, obstacles: [low, high])
        #expect(placement.bottomPadding == 110)  // 600 - 500 + 10
    }

    @Test("Controles no alto da janela são ignorados")
    func topControlsIgnored() {
        let top = CGRect(x: 400, y: 10, width: 300, height: 40)
        let placement = NowPlayingPlacement(container: container, obstacles: [top])
        #expect(placement.bottomPadding == 18)
    }

    @Test("Numa janela estreita, a cápsula encolhe até as margens")
    func narrowWindowShrinksThePill() {
        let narrow = CGSize(width: 200, height: 400)
        let placement = NowPlayingPlacement(container: narrow, obstacles: [])
        #expect(placement.maxWidth == 164)  // 200 - 2 * 18
        #expect(placement.originX == 18)
    }
}
