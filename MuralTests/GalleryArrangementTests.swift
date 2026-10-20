import CoreGraphics
import Testing

@testable import Mural

@Suite("Geometria da pasta")
struct GalleryArrangementTests {
    private let metrics = GalleryArrangement.Metrics()

    /// Cartões em retrato (altura 1,3 × largura), como fotos e notas.
    private func arrange(_ lanes: [GalleryLane], width: CGFloat) -> GalleryArrangement {
        GalleryArrangement(width: width, lanes: lanes, metrics: metrics) { _, columnWidth in columnWidth * 1.3 }
    }

    @Test("Um item de cada faixa fica lado a lado, sem vão, e centralizado")
    func oneOfEachStaysTogether() {
        let result = arrange([.media, .notes], width: 1000)
        let media = result.frames[0]
        let note = result.frames[1]
        #expect(note.minX - media.maxX == metrics.laneSpacing)
        #expect(media.width == metrics.maxColumnWidth)
        #expect(note.width == metrics.maxColumnWidth * metrics.noteWidthRatio)
        let leftMargin = media.minX
        let rightMargin = 1000 - note.maxX
        #expect(abs(leftMargin - rightMargin) < 0.5)
    }

    @Test("Uma faixa nunca tem mais colunas que cartões")
    func columnsNeverExceedItems() {
        let result = arrange([.media, .media], width: 1400)
        let distinctColumns = Set(result.frames.map(\.minX))
        #expect(distinctColumns.count == 2)
        #expect(result.frames[1].minX - result.frames[0].maxX == metrics.spacing)
    }

    @Test("Muitos cartões cabem na largura e respeitam o limite de colunas")
    func manyItemsFitTheWidth() {
        let lanes = Array(repeating: GalleryLane.media, count: 9) + Array(repeating: .notes, count: 7)
        let result = arrange(lanes, width: 900)
        #expect(result.frames.allSatisfy { $0.minX >= 0 && $0.maxX <= 900.5 })
        let mediaColumns = Set(result.frames.prefix(9).map(\.minX))
        let noteColumns = Set(result.frames.suffix(7).map(\.minX))
        #expect(mediaColumns.count == metrics.maxMediaColumns)
        #expect(noteColumns.count == metrics.maxNoteColumns)
        #expect(mediaColumns.max()! < noteColumns.min()!, "mídia à esquerda, notas à direita")
    }

    @Test("Com mais cartões que colunas, o excedente entra na coluna mais curta")
    func masonryFillsShortestColumn() {
        // Sozinha, a faixa usa até 4 colunas: os 4 primeiros abrem uma coluna cada.
        let heights: [CGFloat] = [400, 100, 100, 100, 100]
        let result = GalleryArrangement(width: 2000, lanes: Array(repeating: .media, count: 5), metrics: metrics) {
            index, _ in heights[index]
        }
        #expect(result.frames[4].minX == result.frames[1].minX, "o quinto vai para baixo da primeira coluna curta")
        #expect(result.frames[4].minY == 100 + metrics.spacing)
        #expect(result.size.height == 400)
    }

    @Test("Pasta vazia não tem altura")
    func emptyFolder() {
        #expect(arrange([], width: 800).size.height == 0)
    }
}
