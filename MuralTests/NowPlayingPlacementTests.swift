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

    @Test("Com pouco espaço ao lado da barra, sobe para mostrar todos os botões em vez de encolher")
    func liftsInsteadOfCompacting() {
        let bar = CGRect(x: 250, y: 520, width: 500, height: 48)
        let placement = NowPlayingPlacement(container: container, obstacles: [bar])
        #expect(placement.bottomPadding == 90)  // 600 - 520 + 10
        #expect(placement.maxWidth == 420)
    }

    @Test("Controles no alto da janela são ignorados")
    func topControlsIgnored() {
        let top = CGRect(x: 10, y: 10, width: 300, height: 40)
        let placement = NowPlayingPlacement(container: container, obstacles: [top])
        #expect(placement.maxWidth == 420)
        #expect(placement.bottomPadding == 18)
    }

    @Test("À esquerda, a cápsula fica na margem e não sobe se a barra está longe")
    func leadingDockStaysOnMargin() {
        let bar = CGRect(x: 380, y: 520, width: 240, height: 48)
        let placement = NowPlayingPlacement(container: container, obstacles: [bar], dock: .leading, barWidth: 250)
        #expect(placement.originX == 18)
        #expect(placement.maxWidth == 250)
        #expect(placement.bottomPadding == 18)
    }

    @Test("No centro, sobe acima da barra centralizada")
    func centerDockLiftsAboveCenteredBar() {
        let bar = CGRect(x: 380, y: 520, width: 240, height: 48)
        let placement = NowPlayingPlacement(container: container, obstacles: [bar], dock: .center, barWidth: 250)
        #expect(placement.originX == 375)
        #expect(placement.bottomPadding == 90)  // 600 - 520 + 10
    }

    @Test("No centro, sem nada que cruze, fica na margem de baixo")
    func centerDockWithoutObstacle() {
        let zoom = CGRect(x: 880, y: 530, width: 100, height: 40)
        let placement = NowPlayingPlacement(container: container, obstacles: [zoom], dock: .center, barWidth: 250)
        #expect(placement.bottomPadding == 18)
    }

    @Test("À direita, sobe acima do zoom quando se cruzam")
    func trailingDockLiftsAboveZoom() {
        let zoom = CGRect(x: 880, y: 530, width: 100, height: 40)
        let bar = CGRect(x: 380, y: 520, width: 240, height: 48)
        let placement = NowPlayingPlacement(container: container, obstacles: [bar, zoom], dock: .trailing, barWidth: 250)
        #expect(placement.originX == 732)  // 1000 - 18 - 250
        #expect(placement.bottomPadding == 80)  // 600 - 530 + 10
    }

    @Test("Sobe acima do mais alto dos controles que cruzam")
    func liftsAboveTheHighestCrossing() {
        let low = CGRect(x: 700, y: 540, width: 100, height: 40)
        let high = CGRect(x: 900, y: 500, width: 80, height: 60)
        let placement = NowPlayingPlacement(container: container, obstacles: [low, high], dock: .trailing, barWidth: 250)
        #expect(placement.bottomPadding == 110)  // 600 - 500 + 10
    }

    @Test("O ponto mais perto é escolhido pelo meio da cápsula")
    func nearestDock() {
        func nearest(_ midX: CGFloat) -> NowPlayingDock {
            NowPlayingDock.nearest(toMidX: midX, container: container, barWidth: 250)
        }
        #expect(nearest(100) == .leading)
        #expect(nearest(480) == .center)
        #expect(nearest(900) == .trailing)
        #expect(nearest(320) == .leading)
        #expect(nearest(700) == .trailing)
    }
}
