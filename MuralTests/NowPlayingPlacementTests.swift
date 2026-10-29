import CoreGraphics
import Testing

@testable import Mural

@Suite("Lugar do Tocando agora")
@MainActor
struct NowPlayingPlacementTests {
    private let container = CGSize(width: 1000, height: 600)

    @Test("Sem nada embaixo, ocupa a largura até o limite")
    func nothingBelow() {
        let placement = NowPlayingPlacement(container: container, obstacles: [])
        #expect(placement.maxWidth == 420)
        #expect(placement.bottomPadding == 18)
    }

    @Test("Ao lado da barra centralizada")
    func besideCenteredBar() {
        let bar = CGRect(x: 380, y: 520, width: 240, height: 48)
        let placement = NowPlayingPlacement(container: container, obstacles: [bar])
        // 380 - 12 - 18 = 350
        #expect(placement.maxWidth == 350)
        #expect(placement.bottomPadding == 18)
    }

    @Test("Os controles da direita também contam")
    func trailingControlsCount() {
        let bar = CGRect(x: 380, y: 520, width: 240, height: 48)
        let zoom = CGRect(x: 880, y: 530, width: 100, height: 40)
        let placement = NowPlayingPlacement(container: container, obstacles: [zoom, bar])
        #expect(placement.maxWidth == 350)
        let onlyZoom = NowPlayingPlacement(container: container, obstacles: [zoom])
        #expect(onlyZoom.maxWidth == 420)
    }

    @Test("Sem espaço, sobe acima da barra")
    func liftsAboveWhenNoRoom() {
        let narrow = CGSize(width: 520, height: 400)
        let bar = CGRect(x: 140, y: 330, width: 240, height: 48)
        let placement = NowPlayingPlacement(container: narrow, obstacles: [bar])
        #expect(placement.bottomPadding == 80)  // 400 - 330 + 10
        #expect(placement.maxWidth == 420)
    }

    @Test("Controles no alto da janela são ignorados")
    func topControlsIgnored() {
        let top = CGRect(x: 10, y: 10, width: 300, height: 40)
        let placement = NowPlayingPlacement(container: container, obstacles: [top])
        #expect(placement.maxWidth == 420)
        #expect(placement.bottomPadding == 18)
    }
}
