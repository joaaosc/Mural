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

    @Test("Área ocupada vai até a borda do cartão mais distante")
    func extentReachesFarthestCard() {
        #expect(BoardLayout.extent(of: []) == (width: 0, height: 0))
        let item = BoardItem(kind: .sticky, title: "x", position: BoardPoint(x: 100, y: 50))
        let size = BoardLayout.cardSize(for: .sticky)
        let extent = BoardLayout.extent(of: [item])
        #expect(extent.width == 100 + size.width && extent.height == 50 + size.height)
    }

    @Test("Foto usa a proporção do arquivo; os demais, a do tipo")
    func aspectRatios() {
        var photo = BoardItem(kind: .image, title: "foto")
        #expect(BoardLayout.aspectRatio(for: photo) == 0.75)
        photo.imageMetadata = ImageMetadata(pixelWidth: 1600, pixelHeight: 900, fileSizeBytes: 1, colorProfile: nil, palette: [])
        #expect(BoardLayout.aspectRatio(for: photo) == 1600.0 / 900.0)
        #expect(BoardLayout.aspectRatio(for: BoardItem(kind: .sticky, title: "p")) == 1.25)
    }
}
