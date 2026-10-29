import Foundation
import Testing

@testable import MuralKit

@Suite("Redimensionar por qualquer canto")
struct BoardResizeCornerTests {
    // MARK: Apoio

    private func sticky(x: Double, y: Double, size: BoardSize? = nil) -> BoardItem {
        BoardItem(kind: .sticky, title: "Post-it", position: BoardPoint(x: x, y: y), size: size)
    }

    private func photo(x: Double = 400, y: Double = 400, size: BoardSize? = BoardSize(width: 200, height: 150)) -> BoardItem {
        let metadata = ImageMetadata(pixelWidth: 4000, pixelHeight: 3000, fileSizeBytes: 1, colorProfile: nil, palette: [])
        return BoardItem(kind: .image, title: "Foto", position: BoardPoint(x: x, y: y), imageMetadata: metadata, size: size)
    }

    private func size(_ width: Double, _ height: Double) -> BoardSize {
        BoardSize(width: width, height: height)
    }

    /// Os quatro cantos de um quadro, para conferir qual deles ficou parado.
    private func edges(_ frame: (origin: BoardPoint, size: BoardSize)) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        (frame.origin.x, frame.origin.y, frame.origin.x + frame.size.width, frame.origin.y + frame.size.height)
    }

    // MARK: Canto oposto parado

    @Test("Em cada canto, o canto oposto do post-it fica parado e o tamanho acompanha o ponteiro")
    func oppositeCornerStaysFixedForStickies() {
        let item = sticky(x: 300, y: 300, size: size(200, 160))
        let cases: [(ResizeCorner, Double, Double, (Double, Double, Double, Double))] = [
            (.bottomTrailing, 30, 20, (300, 300, 530, 480)),
            (.bottomLeading, -30, 20, (270, 300, 500, 480)),
            (.topTrailing, 30, -20, (300, 280, 530, 460)),
            (.topLeading, -30, -20, (270, 280, 500, 460)),
        ]
        for (corner, dx, dy, expected) in cases {
            let frame = BoardLayout.resizedFrame(of: item, corner: corner, deltaWidth: dx, deltaHeight: dy)
            let edge = edges((frame.origin, frame.size))
            #expect(edge.minX == expected.0 && edge.minY == expected.1 && edge.maxX == expected.2 && edge.maxY == expected.3, "\(corner)")
            #expect(frame.proportion == nil)
        }
    }

    @Test("Encolher pelo canto de cima à esquerda leva a origem para dentro e deixa o canto de baixo parado")
    func shrinkingFromTopLeadingMovesOriginInward() {
        let item = sticky(x: 300, y: 300, size: size(200, 160))
        let frame = BoardLayout.resizedFrame(of: item, corner: .topLeading, deltaWidth: 50, deltaHeight: 40)
        #expect(frame.size == size(150, 120))
        #expect(frame.origin == BoardPoint(x: 350, y: 340))
    }

    @Test("O mínimo também segura o canto oposto parado")
    func minimumKeepsOppositeCornerFixed() {
        let item = sticky(x: 300, y: 300, size: size(200, 160))
        let frame = BoardLayout.resizedFrame(of: item, corner: .topLeading, deltaWidth: 900, deltaHeight: 900)
        #expect(frame.size == BoardLayout.minimumStickySize)
        #expect(edges((frame.origin, frame.size)).maxX == 500)
        #expect(edges((frame.origin, frame.size)).maxY == 460)
    }

    // MARK: Limite no começo do mural

    @Test("O crescimento para a esquerda e para cima para na origem 0, sem mover o canto oposto")
    func growthStopsAtCanvasOrigin() {
        let item = sticky(x: 40, y: 20, size: size(100, 100))
        let frame = BoardLayout.resizedFrame(of: item, corner: .topLeading, deltaWidth: -300, deltaHeight: -300)
        #expect(frame.origin == BoardPoint(x: 0, y: 0))
        #expect(frame.size == size(140, 120))
        #expect(edges((frame.origin, frame.size)).maxX == 140)
        #expect(edges((frame.origin, frame.size)).maxY == 120)
    }

    @Test("Com a proporção mantida, o limite do mural também vale para os dois lados")
    func proportionKeptRespectsCanvasOrigin() {
        let item = sticky(x: 40, y: 400, size: size(100, 100))
        let frame = BoardLayout.resizedFrame(
            of: item, corner: .bottomLeading, deltaWidth: -300, deltaHeight: 300, keepingProportion: true)
        #expect(frame.origin.x >= 0)
        #expect(frame.size.width == frame.size.height)
        #expect(edges((frame.origin, frame.size)).maxX == 140)
        #expect(edges((frame.origin, frame.size)).minY == 400)
    }

    // MARK: Foto

    @Test("O encaixe da foto vale no canto de cima à esquerda, e o canto de baixo à direita fica parado")
    func photoSnapsFromTopLeading() {
        let item = photo()
        // O ponteiro vai 100 para a esquerda e 70 para cima: 300 × 220 está perto de 4:3, e a largura, que mais andou, manda.
        let frame = BoardLayout.resizedFrame(of: item, corner: .topLeading, deltaWidth: -100, deltaHeight: -70)
        #expect(frame.proportion == .original)
        #expect(frame.size == size(300, 225))
        #expect(frame.origin == BoardPoint(x: 300, y: 325))
        #expect(edges((frame.origin, frame.size)).maxX == 600)
        #expect(edges((frame.origin, frame.size)).maxY == 550)
    }

    @Test("No canto de baixo à direita o resultado é o de resizedImageSize e a origem não muda")
    func bottomTrailingMatchesImageSize() {
        let item = photo()
        let frame = BoardLayout.resizedFrame(of: item, corner: .bottomTrailing, deltaWidth: 60, deltaHeight: 60)
        let plain = BoardLayout.resizedImageSize(of: item, deltaWidth: 60, deltaHeight: 60)
        #expect(frame.size == plain.size)
        #expect(frame.proportion == plain.proportion)
        #expect(frame.origin == item.position)
    }

    @Test("Shift mantém a proporção da foto a partir de qualquer canto, sem encaixe")
    func shiftKeepsPhotoProportionFromAnyCorner() {
        let item = photo()
        for corner in ResizeCorner.allCases {
            let dx = corner.isLeading ? -80.0 : 80.0
            let frame = BoardLayout.resizedFrame(of: item, corner: corner, deltaWidth: dx, deltaHeight: 0, keepingProportion: true)
            #expect(frame.proportion == nil, "\(corner)")
            #expect(frame.size == size(280, 210), "\(corner)")
        }
    }

    // MARK: Texto livre

    @Test("Texto livre: o canto oposto fica parado e o limite do mural vale")
    func freeTextCorners() {
        let text = BoardFreeText(text: "Texto", position: BoardPoint(x: 100, y: 50), size: size(200, 100))
        let top = BoardLayout.resizedFrame(of: text, corner: .topLeading, deltaWidth: -40, deltaHeight: -20)
        #expect(top.size == size(240, 120))
        #expect(top.origin == BoardPoint(x: 60, y: 30))

        let capped = BoardLayout.resizedFrame(of: text, corner: .topLeading, deltaWidth: -999, deltaHeight: -999)
        #expect(capped.origin == BoardPoint(x: 0, y: 0))
        #expect(capped.size == size(300, 150))

        let trailing = BoardLayout.resizedFrame(of: text, corner: .topTrailing, deltaWidth: 30, deltaHeight: -10)
        #expect(trailing.size == size(230, 110))
        #expect(trailing.origin == BoardPoint(x: 100, y: 40))
    }
}
