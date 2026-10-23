import CoreGraphics
import Foundation
import Testing

@testable import Mural

@Suite("Geometria do post-it solto na pasta")
struct StickyPlacementTests {
    @Test("O lugar (0, 0) põe o post-it no meio da área, no topo")
    func originIsTheMiddleOfTheArea() {
        let frame = StickyPlacement.frame(for: .zero, width: 1000)
        #expect(frame.minX == 500)
        #expect(frame.minY == 0)
        #expect(frame.size == CGSize(width: 180, height: 144))
    }

    @Test("Numa janela estreita, o post-it encosta na borda da área")
    func clampsToTheSidesOfTheArea() {
        #expect(StickyPlacement.frame(for: CGPoint(x: -900, y: 20), width: 1000).minX == 0)
        #expect(StickyPlacement.frame(for: CGPoint(x: 400, y: 20), width: 1000).minX == 820)
    }

    @Test("Numa área mais estreita que o post-it, ele fica na borda esquerda")
    func areaNarrowerThanTheSticky() {
        #expect(StickyPlacement.frame(for: CGPoint(x: 30, y: 0), width: 120).minX == 0)
        #expect(StickyPlacement.frame(for: CGPoint(x: -30, y: 0), width: 120).minX == 0)
    }

    @Test("Nunca fica acima do topo")
    func neverAboveTheTop() {
        #expect(StickyPlacement.frame(for: CGPoint(x: 0, y: -50), width: 1000).minY == 0)
    }

    @Test("O lugar guardado a partir da origem devolve o mesmo quadro")
    func positionFromOriginRoundTrips() {
        let position = StickyPlacement.position(forOrigin: CGPoint(x: 100, y: 50), width: 1000)
        #expect(position == CGPoint(x: -400, y: 50))
        #expect(StickyPlacement.frame(for: position, width: 1000).origin == CGPoint(x: 100, y: 50))
    }

    @Test("Largar além da borda guarda o lugar já encostado nela")
    func positionFromOriginStaysInsideTheArea() {
        let right = StickyPlacement.position(forOrigin: CGPoint(x: 950, y: 10), width: 1000)
        #expect(StickyPlacement.frame(for: right, width: 1000).minX == 820)
        let topLeft = StickyPlacement.position(forOrigin: CGPoint(x: -40, y: -30), width: 1000)
        #expect(topLeft == CGPoint(x: -500, y: 0))
    }

    @Test("O post-it novo nasce com o centro no meio do que está à vista")
    func newStickyIsCenteredInTheVisibleRect() {
        let area = CGRect(x: 104, y: 70, width: 1000, height: 800)
        let visible = CGRect(x: 0, y: 0, width: 1240, height: 800)
        let rect = StickyPlacement.visibleRectForNewSticky(visible, area: area)
        let place = CGPoint(x: rect.midX, y: rect.midY)
        let frame = StickyPlacement.frame(for: place, width: area.width).offsetBy(dx: area.minX, dy: area.minY)
        #expect(frame.midX == 620)
        #expect(frame.midY == 400)
    }

    @Test("A subpasta sob o ponteiro é a candidata cujo quadro contém o ponto")
    func folderUnderPointerIsTheCandidateContainingIt() {
        let first = UUID()
        let second = UUID()
        let frames = [
            first: CGRect(x: 100, y: 50, width: 200, height: 150),
            second: CGRect(x: 400, y: 50, width: 200, height: 150),
        ]
        let candidates = [first, second]
        #expect(StickyPlacement.folder(under: CGPoint(x: 200, y: 100), frames: frames, among: candidates) == first)
        #expect(StickyPlacement.folder(under: CGPoint(x: 500, y: 100), frames: frames, among: candidates) == second)
    }

    @Test("Fora de todos os quadros, não há subpasta")
    func noFolderOutsideAllFrames() {
        let first = UUID()
        let second = UUID()
        let frames = [
            first: CGRect(x: 100, y: 50, width: 200, height: 150),
            second: CGRect(x: 400, y: 50, width: 200, height: 150),
        ]
        let candidates = [first, second]
        #expect(StickyPlacement.folder(under: CGPoint(x: 350, y: 100), frames: frames, among: candidates) == nil)
        #expect(StickyPlacement.folder(under: CGPoint(x: 200, y: 300), frames: frames, among: candidates) == nil)
        #expect(StickyPlacement.folder(under: CGPoint(x: 200, y: 100), frames: frames, among: []) == nil)
    }

    @Test("Um quadro que não está entre os candidatos é ignorado, e um candidato sem quadro medido não conta")
    func framesOutsideTheCandidatesAreIgnored() {
        let accepted = UUID()
        let refused = UUID()
        let frames = [
            accepted: CGRect(x: 0, y: 0, width: 100, height: 100),
            refused: CGRect(x: 200, y: 0, width: 100, height: 100),
        ]
        let point = CGPoint(x: 250, y: 50)
        #expect(StickyPlacement.folder(under: point, frames: frames, among: [accepted]) == nil)
        #expect(StickyPlacement.folder(under: point, frames: frames, among: [accepted, refused]) == refused)
        #expect(StickyPlacement.folder(under: point, frames: frames, among: [UUID()]) == nil)
    }

    @Test("As bordas de cima e da esquerda do quadro contam como dentro")
    func topAndLeftEdgesCountAsInside() {
        let id = UUID()
        let frames = [id: CGRect(x: 100, y: 50, width: 200, height: 150)]
        #expect(StickyPlacement.folder(under: CGPoint(x: 100, y: 120), frames: frames, among: [id]) == id)
        #expect(StickyPlacement.folder(under: CGPoint(x: 180, y: 50), frames: frames, among: [id]) == id)
        #expect(StickyPlacement.folder(under: CGPoint(x: 100, y: 50), frames: frames, among: [id]) == id)
    }

    @Test("As bordas de baixo e da direita do quadro contam como fora")
    func bottomAndRightEdgesCountAsOutside() {
        let id = UUID()
        let frames = [id: CGRect(x: 100, y: 50, width: 200, height: 150)]
        #expect(StickyPlacement.folder(under: CGPoint(x: 300, y: 120), frames: frames, among: [id]) == nil)
        #expect(StickyPlacement.folder(under: CGPoint(x: 180, y: 200), frames: frames, among: [id]) == nil)
        #expect(StickyPlacement.folder(under: CGPoint(x: 300, y: 200), frames: frames, among: [id]) == nil)
    }
}
