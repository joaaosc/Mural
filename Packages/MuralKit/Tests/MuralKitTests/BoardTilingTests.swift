import Foundation
import Testing

@testable import MuralKit

@MainActor
@Suite("Organizar em mosaico")
struct BoardTilingTests {
    private func item(_ kind: ItemKind, x: Double, y: Double, title: String = "") -> BoardItem {
        BoardItem(kind: kind, title: title, position: BoardPoint(x: x, y: y))
    }

    private func frame(of item: BoardItem, at point: BoardPoint) -> CGRect {
        let size = BoardLayout.cardSize(for: item.kind)
        return CGRect(x: point.x, y: point.y, width: size.width, height: size.height)
    }

    /// Mistura de tipos e tamanhos espalhados, como num mural de verdade (e com cartões sobrepostos).
    private var scattered: [BoardItem] {
        [
            item(.text, x: 160, y: 80), item(.sticky, x: 80, y: 110), item(.folder, x: 420, y: 80),
            item(.image, x: 900, y: 40), item(.checklist, x: 160, y: 420), item(.video, x: 300, y: 250),
            item(.pdf, x: 620, y: 600), item(.sticky, x: 400, y: 560), item(.text, x: 300, y: 80),
        ]
    }

    @Test("Mural vazio não gera posições; um cartão só vai para a origem")
    func emptyAndSingle() {
        #expect(BoardTiling.bsp([], aspect: 1.6).isEmpty)
        let only = item(.text, x: 500, y: 700)
        #expect(BoardTiling.bsp([only], aspect: 1.6) == [only.id: BoardPoint(x: 80, y: 80)])
    }

    @Test("Dois cartões numa janela larga ficam lado a lado, com o vão entre eles")
    func twoSideBySide() throws {
        // Datas explícitas: dois `Date.now` seguidos podem cair no mesmo microssegundo e empatar.
        let first = BoardItem(
            kind: .text, title: "", createdAt: Date(timeIntervalSince1970: 1), position: BoardPoint(x: 0, y: 0))
        let second = BoardItem(
            kind: .text, title: "", createdAt: Date(timeIntervalSince1970: 2), position: BoardPoint(x: 600, y: 0))
        let positions = BoardTiling.bsp([second, first], aspect: 1.6)
        let left = try #require(positions[first.id])
        let right = try #require(positions[second.id])
        #expect(left == BoardPoint(x: 80, y: 80))
        #expect(right == BoardPoint(x: 80 + BoardLayout.cardSize(for: .text).width + 24, y: 80))
    }

    @Test("Todos os cartões ganham bloco, sem sobreposição e com vão de 24 pt; o resultado se repete")
    func noOverlapAndGap() throws {
        let items = scattered
        let positions = BoardTiling.bsp(items, aspect: 1.6)
        #expect(Set(positions.keys) == Set(items.map(\.id)))
        let frames = try items.map { try frame(of: $0, at: #require(positions[$0.id])) }
        for (index, lhs) in frames.enumerated() {
            for rhs in frames[(index + 1)...] {
                // Afastados ao menos o vão: crescer cada um 12 pt para cada lado ainda não encosta.
                #expect(!lhs.insetBy(dx: -11.9, dy: -11.9).intersects(rhs.insetBy(dx: -11.9, dy: -11.9)))
            }
        }
        #expect(BoardTiling.bsp(items, aspect: 1.6) == positions)
    }

    @Test("O formato da janela decide o formato do mosaico")
    func followsAspect() throws {
        let items = scattered
        func bounds(_ aspect: Double) throws -> CGRect {
            try items.map { try frame(of: $0, at: #require(BoardTiling.bsp(items, aspect: aspect)[$0.id])) }
                .reduce(CGRect.null) { $0.union($1) }
        }
        let wide = try bounds(3)
        let tall = try bounds(0.4)
        #expect(wide.width > wide.height)
        #expect(tall.height > tall.width)
    }

    @Test("O cartão mais antigo fica primeiro; empate segue a ordem da lista")
    func insertionOrder() {
        let now = Date.now
        let older = BoardItem(kind: .text, title: "", createdAt: now.addingTimeInterval(-60), position: BoardPoint(x: 900, y: 900))
        let newer = BoardItem(kind: .text, title: "", createdAt: now, position: BoardPoint(x: 0, y: 0))
        let tie = BoardItem(kind: .sticky, title: "", createdAt: now, position: BoardPoint(x: 0, y: 0))
        #expect(BoardTiling.insertionOrder([newer, tie, older]).map(\.id) == [older.id, newer.id, tie.id])
        #expect(BoardTiling.bsp([newer, tie, older], aspect: 1.6)[older.id] == BoardPoint(x: 80, y: 80))
    }

    @Test("Organizar um mural já organizado não muda nada")
    func tilingIsStable() throws {
        let items = scattered
        let first = BoardTiling.bsp(items, aspect: 1.6)
        let tiled = try items.map { item in
            var copy = item
            copy.position = try #require(first[item.id])
            return copy
        }
        #expect(BoardTiling.bsp(tiled, aspect: 1.6) == first)
    }

    @Test("Tamanhos escolhidos são preservados e não mudam ao reorganizar de novo")
    func customSizesAreStable() throws {
        let large = BoardItem(
            kind: .sticky, title: "Grande", createdAt: Date(timeIntervalSince1970: 1),
            position: BoardPoint(x: 900, y: 700), size: BoardSize(width: 220, height: 220))
        let small = BoardItem(
            kind: .sticky, title: "Pequeno", createdAt: Date(timeIntervalSince1970: 2),
            position: BoardPoint(x: 20, y: 30), size: BoardSize(width: 80, height: 80))

        let first = BoardTiling.bsp([small, large], aspect: 1.6)
        #expect(try #require(first[large.id]) == BoardPoint(x: 80, y: 80))
        #expect(try #require(first[small.id]) == BoardPoint(x: 80 + 220 + 24, y: 80))

        let tiled = try [large, small].map { item in
            var copy = item
            copy.position = try #require(first[item.id])
            return copy
        }
        #expect(BoardTiling.bsp(tiled, aspect: 1.6) == first)
    }

    @Test("Mudar várias posições mantém a ordem da lista e ignora cartões de pasta")
    func setPositionsKeepsOrder() {
        let folder = BoardItem(kind: .folder, title: "Pasta")
        let loose = item(.text, x: 10, y: 10)
        let other = item(.sticky, x: 20, y: 20)
        let inside = BoardItem(kind: .text, title: "Dentro", parentID: folder.id)
        var board = Board(items: [loose, folder, other, inside])
        let changed = board.setPositions([
            loose.id: BoardPoint(x: 300, y: 300), other.id: other.position, inside.id: BoardPoint(x: 5, y: 5),
        ])
        #expect(changed == 1)
        #expect(board.items.map(\.id) == [loose.id, folder.id, other.id, inside.id])
        #expect(board.item(id: loose.id)?.position == BoardPoint(x: 300, y: 300))
        #expect(board.item(id: inside.id)?.position == inside.position)
    }

    @Test("Organizar devolve só onde estavam os cartões que mudaram")
    func arrangeReturnsPrevious() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MuralTiling-\(UUID().uuidString)")
        let model = BoardModel(store: BoardStore(directory: directory), seedIfEmpty: false)
        let note = model.createNote()
        let sticky = model.createSticky()
        let previous = model.arrange([note.id: BoardPoint(x: 500, y: 500), sticky.id: sticky.position])
        #expect(previous == [note.id: note.position])
        #expect(model.item(id: note.id)?.position == BoardPoint(x: 500, y: 500))
        #expect(model.arrange([note.id: BoardPoint(x: 500, y: 500)]).isEmpty)
    }
}
