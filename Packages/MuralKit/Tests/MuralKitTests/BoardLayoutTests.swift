import Testing

@testable import MuralKit

@Suite("Posição de cartões novos")
struct BoardLayoutTests {
    @Test("Mural vazio usa a origem")
    func emptyBoard() {
        #expect(BoardLayout.freePosition(for: .sticky, avoiding: []) == BoardPoint(x: 80, y: 80))
    }

    @Test("Cartão novo não se sobrepõe aos existentes")
    func avoidsOverlap() {
        let board = SampleBoard.make()
        let p = BoardLayout.freePosition(for: .image, avoiding: board.rootItems)
        let size = BoardLayout.cardSize(for: .image)
        for other in board.rootItems {
            let s = BoardLayout.cardSize(for: other.kind)
            #expect(!BoardLayout.overlaps(p, size, other.position, s, gap: 0), "colide com \(other.title)")
        }
    }
}
