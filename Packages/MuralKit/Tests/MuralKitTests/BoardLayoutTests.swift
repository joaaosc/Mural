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

    @Test("Centro e limites de mural vazio")
    func emptyBoardCenterAndBounds() {
        #expect(BoardLayout.bounds(of: []) == nil)
        #expect(BoardLayout.center(of: []) == .zero)
    }

    @Test("Centro e limites calculados a partir dos cartões")
    func centerAndBoundsFromItems() {
        // Sticky tem tamanho (110, 110)
        let a = BoardItem(kind: .sticky, title: "a", position: BoardPoint(x: 100, y: 50))
        let boundsA = BoardLayout.bounds(of: [a])
        #expect(boundsA?.minX == 100)
        #expect(boundsA?.minY == 50)
        #expect(boundsA?.maxX == 210)
        #expect(boundsA?.maxY == 160)
        #expect(BoardLayout.center(of: [a]) == BoardPoint(x: 155, y: 105))

        // Link tem tamanho (150, 170) na posição (300, 200) -> vai até (450, 370)
        let b = BoardItem(kind: .link, title: "b", position: BoardPoint(x: 300, y: 200))
        let boundsBoth = BoardLayout.bounds(of: [a, b])
        #expect(boundsBoth?.minX == 100)
        #expect(boundsBoth?.minY == 50)
        #expect(boundsBoth?.maxX == 450)
        #expect(boundsBoth?.maxY == 370)
        #expect(BoardLayout.center(of: [a, b]) == BoardPoint(x: 275, y: 210))
    }

    @Test("Foto usa a proporção do arquivo; os demais, a do tipo")
    func aspectRatios() {
        var photo = BoardItem(kind: .image, title: "foto")
        #expect(BoardLayout.aspectRatio(for: photo) == 0.75)
        photo.imageMetadata = ImageMetadata(pixelWidth: 1600, pixelHeight: 900, fileSizeBytes: 1, colorProfile: nil, palette: [])
        #expect(BoardLayout.aspectRatio(for: photo) == 1600.0 / 900.0)
        #expect(BoardLayout.aspectRatio(for: BoardItem(kind: .sticky, title: "p")) == 1.25)
    }

    @Test("Link tem tamanho e proporção próprios")
    func linkSizeAndAspectRatio() {
        let size = BoardLayout.cardSize(for: .link)
        #expect(size.width == 150 && size.height == 170)
        #expect(BoardLayout.aspectRatio(for: BoardItem(kind: .link, title: "apple.com")) == 0.85)
        let link = BoardItem(kind: .link, title: "apple.com", position: BoardPoint(x: 100, y: 50))
        let extent = BoardLayout.extent(of: [link])
        #expect(extent.width == 100 + size.width && extent.height == 50 + size.height)
    }
}
