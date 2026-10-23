import Foundation
import Testing

@testable import MuralKit

@Suite("Legendas e posição de importação")
struct BoardCaptionAndImportTests {
    @Test("Legenda nova fica separada do corpo e exige a versão 10")
    func captionUsesSeparateField() throws {
        let item = BoardItem(kind: .image, title: "Imagem", text: nil, caption: "Sala")
        let board = Board(items: [item])
        #expect(item.text == nil)
        #expect(item.caption == "Sala")
        #expect(board.requiredFormatVersion == 10)
        let roundTrip = try JSONDecoder().decode(Board.self, from: JSONEncoder().encode(board))
        #expect(roundTrip.item(id: item.id)?.caption == "Sala")
        #expect(roundTrip.item(id: item.id)?.text == nil)
    }

    @Test("Texto legado de imagem migra para legenda sem contaminar o corpo")
    func legacyImageTextMigrates() throws {
        let item = BoardItem(kind: .image, title: "Imagem", caption: "Sala")
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        object.removeValue(forKey: "caption")
        object["text"] = "Legenda antiga"
        let decoded = try JSONDecoder().decode(BoardItem.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.caption == "Legenda antiga")
        #expect(decoded.text == nil)
    }

    @Test("Importação próxima ao centro evita sobreposição no lote")
    func importPositionsAvoidOverlap() {
        let anchor = BoardPoint(x: 500, y: 400)
        let positions = BoardLayout.importPositions(
            kinds: [.image, .sticky, .pdf], anchor: anchor, avoiding: [])
        #expect(positions.count == 3)
        for (index, position) in positions.enumerated() {
            let size = BoardLayout.cardSize(for: [.image, .sticky, .pdf][index])
            #expect(position.x >= 0)
            #expect(position.y >= 0)
            for previousIndex in 0..<index {
                let previousSize = BoardLayout.cardSize(for: [.image, .sticky, .pdf][previousIndex])
                #expect(!BoardLayout.overlaps(position, size, positions[previousIndex], previousSize, gap: 0))
            }
        }
    }

    @Test("Fallback de importação respeita o tamanho real dos cartões existentes")
    func importFallbackPreservesOccupiedSizes() {
        let anchor = BoardPoint(x: 500, y: 400)
        let blockerPositions = BoardLayout.importPositions(
            kinds: [.sticky, .sticky, .sticky, .sticky], anchor: anchor, avoiding: [])
        let blockers = blockerPositions.map {
            BoardItem(kind: .video, title: "Vídeo", position: $0)
        }

        let position = BoardLayout.importPositions(kinds: [.sticky], anchor: anchor, avoiding: blockers)[0]
        let size = BoardLayout.cardSize(for: .sticky)

        for blocker in blockers {
            #expect(
                !BoardLayout.overlaps(
                    position, size, blocker.position, BoardLayout.cardSize(for: blocker.kind), gap: 24))
        }
    }
}
