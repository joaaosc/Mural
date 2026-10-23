import Foundation
import Testing

@testable import MuralKit

@Suite("Textos livres")
struct BoardFreeTextTests {
    @Test("Normalização respeita 280 caracteres sem cortar grafemas")
    func normalizesByCharacter() {
        let value = String(repeating: "🙂", count: BoardFreeText.maximumCharacters + 20)
        let text = BoardFreeText(text: "  \(value)  ")
        #expect(text.text.count == BoardFreeText.maximumCharacters)
        #expect(text.text.allSatisfy { $0 == "🙂" })
    }

    @Test("Mural antigo decodifica sem a coleção de textos livres")
    func decodesLegacyBoardWithoutCollection() throws {
        let board = Board(items: [BoardItem(kind: .text, title: "Legado")])
        let data = try JSONEncoder().encode(board)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var legacy = object
        legacy.removeValue(forKey: "freeTexts")
        let decoded = try JSONDecoder().decode(Board.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.freeTexts.isEmpty)
        #expect(decoded.items == board.items)
        #expect(decoded.formatVersion == board.formatVersion)
    }

    @Test("Texto livre eleva a versão apenas quando é usado")
    func formatVersionChangesOnlyWhenUsed() {
        #expect(Board().formatVersion == 1)
        let text = BoardFreeText(text: "Olá")
        let board = Board(freeTexts: [text])
        #expect(board.formatVersion == 7)
        #expect(board.requiredFormatVersion == 7)
    }

    @Test("Geometria quadrada, extent, hit-test e posição livre")
    func squareGeometry() {
        let text = BoardFreeText(text: "x", position: BoardPoint(x: 100, y: 50))
        #expect(BoardLayout.freeTextSide == 180)
        #expect(BoardLayout.freeTextSize == (width: 180, height: 180))
        #expect(BoardLayout.extent(of: [], freeTexts: [text]) == (width: 280, height: 230))
        #expect(BoardLayout.freeTextID(at: BoardPoint(x: 100, y: 50), among: [text]) == text.id)
        #expect(BoardLayout.freeTextID(at: BoardPoint(x: 280, y: 230), among: [text]) == nil)
        let next = BoardLayout.freeTextPosition(avoiding: [], freeTexts: [text])
        #expect(!BoardLayout.overlaps(next, BoardLayout.freeTextSize, text.position, BoardLayout.freeTextSize, gap: 0))
    }

    @Test("BoardModel cria, move, atualiza, apaga e reabre texto livre")
    @MainActor
    func modelLifecyclePersists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MuralFreeText-\(UUID().uuidString)")
        let store = BoardStore(directory: directory)
        let model = BoardModel(store: store, seedIfEmpty: false)
        let created = model.createFreeText(String(repeating: "a", count: 400), at: BoardPoint(x: -10, y: 12.7))
        #expect(created.text.count == BoardFreeText.maximumCharacters)
        #expect(created.position == BoardPoint(x: 0, y: 13))
        #expect(model.updateFreeText(created.id, text: "  atualizado  "))
        #expect(model.moveFreeText(created.id, to: BoardPoint(x: -4, y: 22.4)))
        #expect(model.freeText(id: created.id)?.position == BoardPoint(x: 0, y: 22))
        let reopened = BoardModel(store: store, seedIfEmpty: false)
        #expect(reopened.freeText(id: created.id)?.text == "atualizado")
        #expect(reopened.deleteFreeText(created.id))
        #expect(BoardModel(store: store, seedIfEmpty: false).freeText(id: created.id) == nil)
        try? FileManager.default.removeItem(at: directory)
    }
}
