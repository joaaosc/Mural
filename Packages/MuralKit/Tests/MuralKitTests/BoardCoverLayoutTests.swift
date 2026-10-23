import Foundation
import Testing

@testable import MuralKit

@Suite("Enquadramento da capa do mural")
struct BoardCoverLayoutTests {
    private let width = 320.0
    private let height = 200.0

    private func card(_ kind: ItemKind = .sticky, x: Double = 0, y: Double = 0, createdAt: Date = Date(timeIntervalSince1970: 0))
        -> BoardItem
    {
        BoardItem(kind: kind, title: "Cartão", createdAt: createdAt, position: BoardPoint(x: x, y: y))
    }

    private func freeText(x: Double, y: Double) -> BoardFreeText {
        BoardFreeText(text: "Texto", position: BoardPoint(x: x, y: y))
    }

    private func layout(_ board: Board, maximumItems: Int = 200) -> BoardCoverLayout {
        BoardCoverLayout.make(for: board, coverWidth: width, coverHeight: height, maximumItems: maximumItems)
    }

    private func isClose(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 1e-9
    }

    private func isClose(_ a: BoardPoint, _ b: BoardPoint) -> Bool {
        isClose(a.x, b.x) && isClose(a.y, b.y)
    }

    // MARK: Mural vazio

    @Test("Mural vazio não desenha nada, fica na escala máxima e com as origens em zero")
    func emptyBoard() {
        let result = layout(Board())

        #expect(result.isEmpty)
        #expect(result.items.isEmpty && result.freeTexts.isEmpty)
        #expect(result.scale == 0.6)
        #expect(result.contentOrigin == .zero)
        #expect(result.coverOrigin == .zero)

        let smaller = BoardCoverLayout.make(for: Board(), coverWidth: width, coverHeight: height, maximumScale: 0.4)
        #expect(smaller.scale == 0.4)
    }

    @Test("Sem cartões que caibam no limite e sem textos, a capa fica vazia")
    func zeroMaximumItemsLeavesAnEmptyLayout() {
        let board = Board(items: [card(), card(x: 300)])

        for limit in [0, -5] {
            let result = layout(board, maximumItems: limit)
            #expect(result.isEmpty, "limite \(limit)")
            #expect(result.scale == 0.6 && result.contentOrigin == .zero && result.coverOrigin == .zero)
        }
    }

    // MARK: Um cartão

    @Test("Um post-it numa capa de 320x200 com margem 12 vai a 0,6 e fica centralizado em (127, 67)")
    func singleStickyIsCentered() {
        #expect(BoardLayout.cardSize(for: .sticky) == (110, 110), "controle: o tamanho do post-it")
        let sticky = card(.sticky, x: 0, y: 0)

        let result = layout(Board(items: [sticky]))

        #expect(!result.isEmpty)
        #expect(result.items == [sticky])
        #expect(result.scale == 0.6, "um mural pequeno não é ampliado")
        #expect(result.contentOrigin == .zero)
        #expect(isClose(result.coverOrigin, BoardPoint(x: 127, y: 67)))
    }

    @Test("O cartão pode estar longe da origem: a origem do conteúdo é a posição dele e a centralização não muda")
    func contentOriginFollowsTheCardPosition() {
        let result = layout(Board(items: [card(.sticky, x: 500, y: 300)]))

        #expect(result.contentOrigin == BoardPoint(x: 500, y: 300))
        #expect(isClose(result.coverOrigin, BoardPoint(x: 127, y: 67)))
        #expect(isClose(result.coverPoint(for: BoardPoint(x: 500, y: 300)), BoardPoint(x: 127, y: 67)))
        // O canto oposto do post-it (110 x 110 a 0,6 = 66 x 66).
        #expect(isClose(result.coverPoint(for: BoardPoint(x: 610, y: 410)), BoardPoint(x: 193, y: 133)))
    }

    @Test("Um mural grande é reduzido até caber na área útil, a capa menos a margem de cada lado")
    func largeBoardIsScaledToFit() {
        // Dois post-its: o conteúdo vai de x 0 a 4110 e de y 0 a 110, e a largura é que limita.
        let wide = layout(Board(items: [card(x: 0), card(x: 4_000)]))
        #expect(isClose(wide.scale, 296.0 / 4_110.0))
        #expect(isClose(wide.coverOrigin.x, 12), "ocupa a largura útil inteira, de 12 a 308")

        // Dois post-its um sobre o outro na vertical: a altura é que limita (área útil de 176).
        let tall = layout(Board(items: [card(x: 0, y: 0), card(x: 0, y: 1_000)]))
        #expect(isClose(tall.scale, 176.0 / 1_110.0))
        #expect(isClose(tall.coverOrigin.y, 12))
    }

    // MARK: Vários cartões

    @Test("Dois post-its em x 0 e 2000: escala 296/2110 e o ponto (2000, 0) cai no lugar certo")
    func twoStickiesFarApart() {
        let result = layout(Board(items: [card(x: 0), card(x: 2_000)]))
        let scale = 296.0 / 2_110.0

        #expect(isClose(result.scale, scale))
        #expect(result.contentOrigin == .zero)
        #expect(isClose(result.coverOrigin, BoardPoint(x: 12, y: (200 - 110 * scale) / 2)))
        #expect(isClose(result.coverPoint(for: BoardPoint(x: 2_000, y: 0)), BoardPoint(x: 12 + 2_000 * scale, y: (200 - 110 * scale) / 2)))
        // A borda direita do segundo post-it encosta na margem direita da capa.
        #expect(isClose(result.coverPoint(for: BoardPoint(x: 2_110, y: 0)).x, 308))
    }

    @Test("A origem mínima pode ser maior que zero: o conteúdo é medido a partir do menor x e do menor y")
    func minimumOriginAboveZero() {
        // Post-it em (400, 300) e nota (120 x 150) em (700, 500): o conteúdo vai de 400 a 820 e de 300 a 650.
        let result = layout(Board(items: [card(.sticky, x: 400, y: 300), card(.text, x: 700, y: 500)]))
        let scale = 176.0 / 350.0

        #expect(result.contentOrigin == BoardPoint(x: 400, y: 300))
        #expect(isClose(result.scale, scale), "limita a altura: 350 pontos de conteúdo em 176 de área útil")
        #expect(isClose(result.coverOrigin, BoardPoint(x: (320 - 420 * scale) / 2, y: 12)))
        #expect(result.coverPoint(for: result.contentOrigin) == result.coverOrigin)
    }

    @Test("O retângulo de cada tipo de cartão usa o tamanho de BoardLayout.cardSize")
    func contentUsesEachKindSize() {
        let image = BoardLayout.cardSize(for: .image)
        let board = Board(items: [card(.reminder, x: 0, y: 0), card(.image, x: 1_000, y: 2_000)])

        let result = layout(board)

        // O conteúdo termina no canto inferior direito da imagem, que é o cartão mais distante.
        let contentWidth = 1_000 + image.width
        let contentHeight = 2_000 + image.height
        let scale = min(296 / contentWidth, 176 / contentHeight, 0.6)
        #expect(isClose(result.scale, scale))
        #expect(isClose(result.coverOrigin, BoardPoint(x: (320 - contentWidth * scale) / 2, y: (200 - contentHeight * scale) / 2)))
    }

    @Test("A margem grande demais deixa 1 ponto de área útil, e a escala continua positiva")
    func hugePaddingKeepsOnePointOfUsableArea() {
        let result = BoardCoverLayout.make(for: Board(items: [card()]), coverWidth: width, coverHeight: height, padding: 200)

        #expect(isClose(result.scale, 1.0 / 110.0))
        #expect(result.scale > 0)
        #expect(isClose(result.coverOrigin, BoardPoint(x: (320 - 110 * result.scale) / 2, y: (200 - 110 * result.scale) / 2)))
    }

    @Test("A escala máxima também pode ser trocada")
    func maximumScaleIsConfigurable() {
        let board = Board(items: [card()])

        #expect(BoardCoverLayout.make(for: board, coverWidth: width, coverHeight: height, maximumScale: 0.3).scale == 0.3)
        // A capa pequena limita antes da escala máxima: a área útil é de 76 x 76 e o post-it tem 110.
        let small = BoardCoverLayout.make(for: board, coverWidth: 100, coverHeight: 100, maximumScale: 5)
        #expect(isClose(small.scale, 76.0 / 110.0))
    }

    // MARK: Textos livres

    @Test("Só texto livre: o quadrado fixo de 180 pontos faz o conteúdo")
    func freeTextOnly() {
        #expect(BoardLayout.freeTextSide == 180, "controle: o lado do texto livre")
        let text = freeText(x: 50, y: 70)

        let result = layout(Board(freeTexts: [text]))

        #expect(!result.isEmpty)
        #expect(result.items.isEmpty)
        #expect(result.freeTexts == [text])
        #expect(result.scale == 0.6)
        #expect(result.contentOrigin == BoardPoint(x: 50, y: 70))
        #expect(isClose(result.coverOrigin, BoardPoint(x: 106, y: 46)))
    }

    @Test("O texto livre alto numa capa baixa é limitado pela altura")
    func freeTextLimitedByHeight() {
        let result = BoardCoverLayout.make(for: Board(freeTexts: [freeText(x: 0, y: 0)]), coverWidth: 320, coverHeight: 100)

        #expect(isClose(result.scale, 76.0 / 180.0))
        #expect(isClose(result.coverOrigin, BoardPoint(x: 122, y: 12)))
    }

    @Test("Cartões e textos livres entram juntos no mesmo retângulo de conteúdo")
    func itemsAndFreeTextsShareTheBounds() {
        // O cartão vai de (0, 0) a (110, 110); o texto, de (300, 200) a (480, 380).
        let sticky = card(.sticky, x: 0, y: 0)
        let text = freeText(x: 300, y: 200)

        let result = layout(Board(items: [sticky], freeTexts: [text]))
        let scale = 176.0 / 380.0

        #expect(result.items == [sticky] && result.freeTexts == [text])
        #expect(result.contentOrigin == .zero)
        #expect(isClose(result.scale, scale))
        #expect(isClose(result.coverOrigin, BoardPoint(x: (320 - 480 * scale) / 2, y: 12)))
    }

    @Test("O texto livre à esquerda do cartão puxa a origem do conteúdo")
    func freeTextCanDefineTheOrigin() {
        let result = layout(Board(items: [card(x: 400, y: 400)], freeTexts: [freeText(x: 100, y: 450)]))

        #expect(result.contentOrigin == BoardPoint(x: 100, y: 400))
    }

    @Test("Os textos livres não têm limite, mesmo quando os cartões passam do máximo")
    func freeTextsAreNotLimited() {
        let texts = (0..<5).map { freeText(x: Double($0) * 200, y: 0) }
        let board = Board(items: [card(), card(x: 200)], freeTexts: texts)

        let result = layout(board, maximumItems: 1)

        #expect(result.items.count == 1)
        #expect(result.freeTexts == texts)
    }

    // MARK: Limite de cartões

    @Test("Passando do limite, ficam os cartões mais recentes, na ordem em que estavam no mural")
    func limitKeepsTheMostRecentInMuralOrder() {
        let date: (Double) -> Date = { Date(timeIntervalSince1970: $0) }
        let a = card(x: 0, createdAt: date(3))
        let b = card(x: 100, createdAt: date(5))
        let c = card(x: 5_000, createdAt: date(1))
        let d = card(x: 300, createdAt: date(4))
        let e = card(x: 9_000, createdAt: date(2))

        let result = layout(Board(items: [a, b, c, d, e]), maximumItems: 3)

        #expect(result.items.map(\.id) == [a.id, b.id, d.id], "os de data 3, 5 e 4, na ordem do mural")
        #expect(result.contentOrigin == .zero)
        // Os dois de fora (x 5000 e 9000) não contam: o conteúdo vai de 0 a 410 e cabe na escala máxima.
        #expect(result.scale == 0.6)
    }

    @Test("O cartão que fica de fora do limite não entra no enquadramento")
    func droppedCardDoesNotAffectTheBounds() {
        let old = card(x: 10_000, y: 10_000, createdAt: Date(timeIntervalSince1970: 1))
        let recent = card(x: 40, y: 60, createdAt: Date(timeIntervalSince1970: 2))

        let result = layout(Board(items: [old, recent]), maximumItems: 1)

        #expect(result.items == [recent])
        #expect(result.contentOrigin == BoardPoint(x: 40, y: 60))
        #expect(result.scale == 0.6)
    }

    @Test("Em empate de data, vale a ordem do mural: ficam os que vêm antes")
    func ties() {
        let same = Date(timeIntervalSince1970: 100)
        let first = card(x: 0, createdAt: same)
        let second = card(x: 100, createdAt: same)
        let third = card(x: 200, createdAt: same)

        let result = layout(Board(items: [first, second, third]), maximumItems: 2)

        #expect(result.items.map(\.id) == [first.id, second.id])
    }

    @Test("Com o limite exato ou folgado, todos os cartões ficam, na ordem do mural")
    func underTheLimitKeepsEverything() {
        let items = (0..<4).map { card(x: Double($0) * 150, createdAt: Date(timeIntervalSince1970: Double(10 - $0))) }

        #expect(layout(Board(items: items), maximumItems: 4).items == items)
        #expect(layout(Board(items: items), maximumItems: 200).items == items)
    }

    @Test("O limite padrão é de 200 cartões soltos")
    func defaultLimitIsTwoHundred() {
        let items = (0..<250).map { card(x: Double($0) * 10, createdAt: Date(timeIntervalSince1970: Double($0))) }

        let result = BoardCoverLayout.make(for: Board(items: items), coverWidth: width, coverHeight: height)

        #expect(result.items.count == 200)
        #expect(result.items.first?.id == items[50].id, "os 50 mais antigos ficaram de fora")
        #expect(result.items.last?.id == items[249].id)
    }

    // MARK: Pastas

    @Test("Cartões dentro de pastas não entram; a pasta solta entra")
    func folderChildrenAreLeftOut() {
        let folder = BoardItem(kind: .folder, title: "Pasta", position: BoardPoint(x: 20, y: 30))
        // A posição de um cartão de pasta não vale no mural: aqui ela é de propósito muito longe.
        let child = BoardItem(kind: .sticky, title: "Dentro", parentID: folder.id, position: BoardPoint(x: 5_000, y: 5_000))
        let loose = card(.text, x: 300, y: 10)

        let result = layout(Board(items: [folder, child, loose]))

        #expect(result.items == [folder, loose])
        #expect(result.contentOrigin == BoardPoint(x: 20, y: 10))
    }

    @Test("Só cartões com pai e nenhum solto: a capa fica vazia, mesmo que a pasta não esteja no mural")
    func onlyCardsInsideFolders() {
        let child = BoardItem(kind: .sticky, title: "Dentro", parentID: UUID(), position: BoardPoint(x: 40, y: 40))

        let result = layout(Board(items: [child]))

        #expect(result.isEmpty)
        #expect(result.contentOrigin == .zero && result.coverOrigin == .zero && result.scale == 0.6)
    }

    // MARK: Conversão de pontos

    @Test("coverPoint é a origem da capa mais a distância ao conteúdo vezes a escala")
    func coverPointFormula() {
        let result = layout(Board(items: [card(x: 400, y: 300), card(.text, x: 700, y: 500)]))
        let point = BoardPoint(x: 550, y: 410)

        let converted = result.coverPoint(for: point)

        #expect(isClose(converted.x, result.coverOrigin.x + (550 - 400) * result.scale))
        #expect(isClose(converted.y, result.coverOrigin.y + (410 - 300) * result.scale))
        #expect(result.coverPoint(for: result.contentOrigin) == result.coverOrigin)
    }

    @Test("Um mural vazio converte pelos zeros e pela escala máxima")
    func emptyLayoutConvertsWithMaximumScale() {
        let result = layout(Board())

        #expect(isClose(result.coverPoint(for: BoardPoint(x: 100, y: 50)), BoardPoint(x: 60, y: 30)))
    }

    @Test("O mesmo mural dá sempre o mesmo enquadramento")
    func layoutIsDeterministic() {
        let board = Board(items: [card(x: 3, y: 4), card(.pdf, x: 900, y: 70)], freeTexts: [freeText(x: 40, y: 500)])

        #expect(layout(board) == layout(board))
    }
}
