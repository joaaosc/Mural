import Foundation
import Testing

@testable import MuralKit

@Suite("Gravar posição e tamanho de uma vez")
struct BoardResizeFrameTests {
    private func sticky(x: Double, y: Double, size: BoardSize? = nil) -> BoardItem {
        BoardItem(kind: .sticky, title: "Post-it", position: BoardPoint(x: x, y: y), size: size)
    }

    private func size(_ width: Double, _ height: Double) -> BoardSize {
        BoardSize(width: width, height: height)
    }

    @Test("setFrame muda posição e tamanho sem mexer na ordem da lista")
    func setFrameKeepsListOrder() {
        let first = sticky(x: 300, y: 300)
        let second = sticky(x: 700, y: 300)
        var board = Board(items: [first, second])
        let changed = board.setFrame(id: first.id, origin: BoardPoint(x: 270.4, y: -5), size: size(140.2, 5_000))
        #expect(changed)
        #expect(board.items.map(\.id) == [first.id, second.id])
        #expect(board.item(id: first.id)?.position == BoardPoint(x: 270, y: 0))
        #expect(board.item(id: first.id)?.size == size(140, 480))
        #expect(board.formatVersion == 11)
        let again = board.setFrame(id: first.id, origin: BoardPoint(x: 270, y: 0), size: size(140, 480))
        #expect(!again, "igual não conta como mudança")
    }

    @Test("setFrame com o tamanho padrão devolve o cartão ao padrão, e uma pasta ou outro tipo recusa")
    func setFrameNormalizesAndRefuses() {
        let item = sticky(x: 100, y: 100, size: size(200, 200))
        let folder = BoardItem(kind: .folder, title: "Pasta", position: BoardPoint(x: 10, y: 10))
        var inside = sticky(x: 0, y: 0)
        inside.parentID = folder.id
        var board = Board(items: [item, folder, inside])
        let reset = board.setFrame(id: item.id, origin: BoardPoint(x: 100, y: 100), size: size(110, 110))
        #expect(reset)
        #expect(board.item(id: item.id)?.size == nil)
        let onFolder = board.setFrame(id: folder.id, origin: BoardPoint(x: 0, y: 0), size: size(300, 300))
        let onInside = board.setFrame(id: inside.id, origin: BoardPoint(x: 5, y: 5), size: size(300, 300))
        #expect(!onFolder)
        #expect(!onInside)
    }

    @Test("setFreeTextFrame normaliza o tamanho e prende a posição, numa só alteração")
    func setFreeTextFrameNormalizes() {
        let text = BoardFreeText(text: "Texto", position: BoardPoint(x: 100, y: 100))
        var board = Board(freeTexts: [text])
        let changed = board.setFreeTextFrame(id: text.id, origin: BoardPoint(x: -20, y: 80.6), size: size(5_000, 10))
        let unknown = board.setFreeTextFrame(id: UUID(), origin: .zero, size: nil)
        #expect(changed)
        #expect(!unknown)
        #expect(board.freeText(id: text.id)?.position == BoardPoint(x: 0, y: 81))
        #expect(board.freeText(id: text.id)?.size == size(BoardLayout.maximumFreeTextSize.width, 60))
    }

    @Test("BoardModel grava posição e tamanho de uma vez e reabre com eles")
    @MainActor
    func modelPersistsFrames() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MuralFrame-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(directory: directory)
        let model = BoardModel(store: store, seedIfEmpty: false)
        let postIt = model.createSticky()
        let text = model.createFreeText("Anotação")

        #expect(model.resize(postIt.id, to: size(200, 160), at: BoardPoint(x: 90, y: 70)))
        #expect(model.resizeFreeText(text.id, to: size(300, 200), at: BoardPoint(x: 50, y: 40)))
        #expect(model.item(id: postIt.id)?.position == BoardPoint(x: 90, y: 70))
        #expect(model.item(id: postIt.id)?.size == size(200, 160))

        let reopened = BoardModel(store: store, seedIfEmpty: false)
        #expect(reopened.item(id: postIt.id)?.position == BoardPoint(x: 90, y: 70))
        #expect(reopened.item(id: postIt.id)?.size == size(200, 160))
        #expect(reopened.freeText(id: text.id)?.position == BoardPoint(x: 50, y: 40))
        #expect(reopened.freeText(id: text.id)?.size == size(300, 200))
    }
}
