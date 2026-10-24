import Foundation
import Testing

@testable import MuralKit

@Suite("Tamanho de post-its e textos livres")
struct BoardResizeTests {
    /// A versão do formato que um tamanho escolhido exige.
    private static let requiredVersion = 11

    // MARK: Apoio

    /// As datas são explícitas: o mosaico ordena por criação, e dois `Date.now` seguidos podem empatar.
    private func sticky(
        _ title: String = "Post-it", x: Double = 0, y: Double = 0, size: BoardSize? = nil, createdAt: Double = 1
    ) -> BoardItem {
        BoardItem(
            kind: .sticky, title: title, createdAt: Date(timeIntervalSince1970: createdAt), position: BoardPoint(x: x, y: y),
            size: size)
    }

    private func freeText(x: Double = 0, y: Double = 0, size: BoardSize? = nil) -> BoardFreeText {
        BoardFreeText(text: "Texto", position: BoardPoint(x: x, y: y), size: size)
    }

    private func square(_ side: Double) -> BoardSize {
        BoardSize(width: side, height: side)
    }

    private func size(_ width: Double, _ height: Double) -> BoardSize {
        BoardSize(width: width, height: height)
    }

    private func isClose(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 1e-9
    }

    /// Sem sobreposição nem com o vão de 24 pontos, medido com o tamanho que cada um de fato tem.
    private func overlapsWithGap(_ point: BoardPoint, newSize: (width: Double, height: Double), _ other: BoardItem) -> Bool {
        BoardLayout.overlaps(point, newSize, other.position, BoardLayout.size(of: other), gap: 24)
    }

    // MARK: Versão do formato

    @Test("O tamanho de um post-it exige a versão 11 só enquanto existe, e a versão volta quando ele sai")
    func stickySizeBumpsTheVersionOnlyWhileItExists() {
        #expect(Board.currentFormatVersion == Self.requiredVersion, "controle: a versão atual do formato")
        let plain = sticky()
        var board = Board(items: [plain])
        #expect(board.formatVersion == 1)

        let grown = board.resize(id: plain.id, to: square(200))
        #expect(grown)
        #expect(board.formatVersion == Self.requiredVersion)
        #expect(board.requiredFormatVersion == Self.requiredVersion)
        #expect(Board(items: board.items).formatVersion == Self.requiredVersion, "criar o mural com o tamanho dá a mesma versão")

        let cleared = board.resize(id: plain.id, to: nil)
        #expect(cleared)
        #expect(board.formatVersion == 1, "sem tamanho escolhido, o mural volta a abrir nas builds anteriores")
        #expect(board.item(id: plain.id)?.size == nil)
    }

    @Test("O tamanho de um texto livre exige a versão 11 só enquanto existe, e o mural volta à 7")
    func freeTextSizeBumpsTheVersionOnlyWhileItExists() {
        let text = freeText()
        var board = Board(freeTexts: [text])
        #expect(board.formatVersion == 7)

        let grown = board.resizeFreeText(id: text.id, to: size(300, 200))
        #expect(grown)
        #expect(board.formatVersion == Self.requiredVersion)
        #expect(board.requiredFormatVersion == Self.requiredVersion)

        let cleared = board.resizeFreeText(id: text.id, to: nil)
        #expect(cleared)
        #expect(board.formatVersion == 7)
        #expect(board.freeText(id: text.id)?.size == nil)
    }

    @Test("Basta um elemento com tamanho para o mural continuar na versão 11")
    func versionStaysWhileAnyElementHasASize() {
        let item = sticky(size: square(200))
        let text = freeText(size: square(300))
        var board = Board(items: [item], freeTexts: [text])
        #expect(board.formatVersion == Self.requiredVersion)

        board.resize(id: item.id, to: nil)
        #expect(board.formatVersion == Self.requiredVersion, "o texto livre ainda tem tamanho")
        board.resizeFreeText(id: text.id, to: nil)
        #expect(board.formatVersion == 7, "sem nenhum tamanho, só o texto livre exige a versão 7")
    }

    @Test("Um mural sem tamanhos continua na versão que já tinha")
    func boardWithoutSizesKeepsItsVersion() {
        #expect(Board(items: [sticky()]).formatVersion == 1)
        #expect(Board(items: [sticky()], freeTexts: [freeText()]).formatVersion == 7)
    }

    // MARK: Gravação

    @Test("Sem tamanho, o campo nem é gravado, e um mural antigo decodifica com os tamanhos padrão")
    func decodesBoardWithoutSizes() throws {
        let board = Board(items: [sticky()], freeTexts: [freeText()])
        let data = try JSONEncoder().encode(board)
        #expect(!String(decoding: data, as: UTF8.self).contains("\"size\""), "o campo só aparece quando há tamanho")

        let decoded = try JSONDecoder().decode(Board.self, from: data)
        let decodedItem = try #require(decoded.items.first)
        let decodedText = try #require(decoded.freeTexts.first)
        #expect(decoded == board)
        #expect(decodedItem.size == nil)
        #expect(decodedText.size == nil)
        #expect(BoardLayout.size(of: decodedItem) == (width: 110, height: 110))
        #expect(BoardLayout.size(of: decodedText) == (width: 180, height: 180))
    }

    @Test("O tamanho escolhido sobrevive a gravar e ler, nos dois tipos")
    func sizeRoundTrips() throws {
        let board = Board(items: [sticky(size: size(200, 150))], freeTexts: [freeText(size: size(300, 200))])
        let decoded = try JSONDecoder().decode(Board.self, from: JSONEncoder().encode(board))
        #expect(decoded == board)
        #expect(decoded.items.first?.size == size(200, 150))
        #expect(decoded.freeTexts.first?.size == size(300, 200))
        #expect(decoded.formatVersion == Self.requiredVersion)
    }

    @Test("O campo size de um JSON escrito à mão é lido nos dois tipos")
    func decodesHandWrittenSize() throws {
        let id = UUID().uuidString
        let json = """
            {
              "formatVersion": 11,
              "items": [
                {"id": "\(id)", "kind": "sticky", "title": "x", "createdAt": 0,
                 "position": {"x": 10, "y": 20}, "size": {"width": 200, "height": 150}}
              ],
              "freeTexts": [
                {"id": "\(UUID().uuidString)", "text": "t", "createdAt": 0,
                 "position": {"x": 0, "y": 0}, "size": {"width": 300, "height": 200}}
              ]
            }
            """
        let board = try JSONDecoder().decode(Board.self, from: Data(json.utf8))
        #expect(board.items.first?.size == size(200, 150))
        #expect(board.freeTexts.first?.size == size(300, 200))
    }

    // MARK: Normalização

    @Test("O tamanho de um post-it é arredondado e preso entre 60 e 480 pontos")
    func stickySizeIsRoundedAndClamped() {
        #expect(BoardLayout.normalizedSize(size(200.4, 199.6), for: .sticky) == square(200))
        #expect(BoardLayout.normalizedSize(size(90, 300), for: .sticky) == size(90, 300), "a proporção não precisa ser quadrada")
        #expect(BoardLayout.normalizedSize(size(10, 10), for: .sticky) == square(60))
        #expect(BoardLayout.normalizedSize(size(5_000, 700), for: .sticky) == square(480))
        #expect(BoardLayout.normalizedSize(size(-50, 0), for: .sticky) == square(60))
        #expect(BoardLayout.minimumStickySize == square(60) && BoardLayout.maximumStickySize == square(480))
    }

    @Test("O tamanho de um texto livre é arredondado e preso entre 100 × 60 e 720 × 540 pontos")
    func freeTextSizeIsRoundedAndClamped() {
        #expect(BoardLayout.normalizedFreeTextSize(size(300.5, 200.4)) == size(301, 200))
        #expect(BoardLayout.normalizedFreeTextSize(size(10, 10)) == size(100, 60))
        #expect(BoardLayout.normalizedFreeTextSize(size(5_000, 5_000)) == size(720, 540))
        #expect(BoardLayout.minimumFreeTextSize == size(100, 60) && BoardLayout.maximumFreeTextSize == size(720, 540))
    }

    @Test("Tamanho igual ao padrão vira nil, para o mural não subir de versão à toa")
    func defaultSizeBecomesNil() {
        #expect(BoardLayout.normalizedSize(square(110), for: .sticky) == nil)
        #expect(BoardLayout.normalizedSize(size(110.4, 109.6), for: .sticky) == nil, "arredonda para o padrão")
        #expect(BoardLayout.normalizedSize(nil, for: .sticky) == nil)
        #expect(BoardLayout.normalizedFreeTextSize(square(180)) == nil)
        #expect(BoardLayout.normalizedFreeTextSize(nil) == nil)
        #expect(BoardLayout.normalizedSize(size(110, 111), for: .sticky) != nil, "só o quadrado exato é o padrão")
    }

    @Test("NaN e infinito viram o tamanho mínimo")
    func invalidSizeBecomesTheMinimum() {
        #expect(BoardLayout.normalizedSize(size(.nan, .infinity), for: .sticky) == square(60))
        #expect(BoardLayout.normalizedSize(size(-.infinity, .nan), for: .sticky) == square(60))
        #expect(BoardLayout.normalizedFreeTextSize(size(.nan, .infinity)) == size(100, 60))
        #expect(BoardLayout.normalizedFreeTextSize(size(.infinity, -.infinity)) == size(100, 60))
    }

    @Test("Redimensionar grava o tamanho normalizado, e o texto livre atualizado ou adicionado também")
    func mutationsStoreTheNormalizedSize() {
        let item = sticky()
        let text = freeText()
        var board = Board(items: [item], freeTexts: [text])

        let resized = board.resize(id: item.id, to: size(10, 9_999.4))
        let resizedText = board.resizeFreeText(id: text.id, to: size(5_000, 59.6))
        #expect(resized && resizedText)
        #expect(board.item(id: item.id)?.size == size(60, 480))
        #expect(board.freeText(id: text.id)?.size == size(720, 60))

        var edited = text
        edited.size = square(5_000)
        board.update(edited)
        #expect(board.freeText(id: text.id)?.size == size(720, 540), "update normaliza o tamanho")
        edited.size = square(180)
        board.update(edited)
        #expect(board.freeText(id: text.id)?.size == nil, "update com o padrão tira o tamanho")

        let added = freeText(x: 500, size: square(10))
        board.add(added)
        #expect(board.freeText(id: added.id)?.size == size(100, 60), "add normaliza o tamanho")
        let addedDefault = freeText(x: 900, size: square(180))
        board.add(addedDefault)
        #expect(board.freeText(id: addedDefault.id)?.size == nil)
    }

    // MARK: Quem pode mudar de tamanho

    @Test("Só o post-it muda de tamanho")
    func onlyStickyIsResizable() {
        for kind in ItemKind.allCases {
            #expect(BoardLayout.isResizable(kind) == (kind == .sticky), "\(kind)")
        }
    }

    @Test("Um cartão que não muda de tamanho recusa o tamanho, e o mural fica como estava")
    func nonResizableKindIsRefused() {
        let before = Board(items: ItemKind.allCases.filter { $0 != .sticky }.map { BoardItem(kind: $0, title: "\($0)") })
        var board = before
        for item in before.items {
            let accepted = board.resize(id: item.id, to: square(200))
            #expect(!accepted, "\(item.kind)")
        }
        #expect(board == before)
        #expect(board.formatVersion == before.formatVersion)
    }

    @Test("Chamadas sem efeito não mudam o mural: id desconhecido, tamanho que já era e voltar ao padrão sem tamanho")
    func ineffectiveCallsChangeNothing() {
        let sized = sticky("Com tamanho", x: 300, size: square(200))
        let plain = sticky("Padrão")
        let text = freeText(size: square(300))
        let plainText = freeText(x: 600)
        let before = Board(items: [plain, sized], freeTexts: [text, plainText])
        let calls: [(name: String, apply: (inout Board) -> Bool)] = [
            ("resize de id desconhecido", { $0.resize(id: UUID(), to: square(200)) }),
            ("resize para o tamanho que já tinha", { $0.resize(id: sized.id, to: square(200)) }),
            ("resize para um tamanho que arredonda para o que já tinha", { $0.resize(id: sized.id, to: size(200.3, 199.8)) }),
            ("resize para o padrão de um post-it que já estava nele", { $0.resize(id: plain.id, to: nil) }),
            ("resize para o quadrado padrão de um post-it sem tamanho", { $0.resize(id: plain.id, to: square(110)) }),
            ("resizeFreeText de id desconhecido", { $0.resizeFreeText(id: UUID(), to: square(200)) }),
            ("resizeFreeText para o tamanho que já tinha", { $0.resizeFreeText(id: text.id, to: square(300)) }),
            ("resizeFreeText para o padrão de um texto que já estava nele", { $0.resizeFreeText(id: plainText.id, to: nil) }),
            ("resizeFreeText para o quadrado padrão de um texto sem tamanho", { $0.resizeFreeText(id: plainText.id, to: square(180)) }),
        ]
        for call in calls {
            var board = before
            let changed = call.apply(&board)
            #expect(!changed, "\(call.name) disse que mudou")
            #expect(board == before, "\(call.name) alterou o mural")
        }
    }

    @Test("Mudar o tamanho não muda a posição nem a ordem da lista")
    func resizeKeepsPositionAndOrder() {
        let first = sticky("A", x: 10, y: 20)
        let second = sticky("B", x: 300, y: 20)
        var board = Board(items: [first, second])

        let resized = board.resize(id: first.id, to: square(200))
        #expect(resized)
        #expect(board.items.map(\.id) == [first.id, second.id], "crescer não leva o cartão para cima dos outros")
        #expect(board.item(id: first.id)?.position == first.position)
    }

    @Test("O post-it guarda o tamanho ao entrar numa pasta e ao voltar ao mural")
    func sizeSurvivesFolderMoves() throws {
        let folder = BoardItem(kind: .folder, title: "Pasta", position: BoardPoint(x: 400, y: 0))
        let item = sticky(x: 10, y: 10, size: square(200))
        var board = Board(items: [folder, item])

        let stored = board.moveIntoFolder(id: item.id, folderID: folder.id)
        #expect(stored)
        #expect(board.item(id: item.id)?.size == square(200), "dentro da pasta o campo é ignorado, mas continua guardado")
        #expect(board.formatVersion == Self.requiredVersion, "o campo continua sendo gravado")
        let resizedInside = board.resize(id: item.id, to: square(300))
        #expect(resizedInside, "o tamanho de um post-it de pasta também pode ser guardado")

        let returnedToBoard = board.moveToBoard(id: item.id, at: BoardPoint(x: 50, y: 50))
        #expect(returnedToBoard)
        let returned = try #require(board.item(id: item.id))
        #expect(returned.size == square(300))
        #expect(BoardLayout.size(of: returned) == (width: 300, height: 300))
    }

    @Test("O tamanho guardado num cartão que não muda de tamanho é ignorado")
    func storedSizeOnNonResizableKindIsIgnored() {
        let photo = BoardItem(kind: .image, title: "Foto", size: square(300))
        #expect(BoardLayout.size(of: photo) == BoardLayout.cardSize(for: .image))
        #expect(BoardLayout.normalizedSize(square(300), for: .image) == nil)
    }

    // MARK: Tamanho mostrado

    @Test("O tamanho de um cartão é o escolhido ou o padrão do tipo, e o de um texto livre, o escolhido ou 180 × 180")
    func sizeOfElements() {
        #expect(BoardLayout.size(of: sticky()) == BoardLayout.cardSize(for: .sticky))
        #expect(BoardLayout.size(of: sticky(size: size(220, 90))) == (width: 220, height: 90))
        #expect(BoardLayout.size(of: freeText()) == BoardLayout.freeTextSize)
        #expect(BoardLayout.size(of: freeText(size: size(360, 120))) == (width: 360, height: 120))
    }

    @Test("Um tamanho guardado fora dos limites, de um mural editado por fora, é preso na hora de desenhar")
    func storedSizeOutsideTheLimitsIsClampedWhenShown() {
        #expect(BoardLayout.size(of: sticky(size: size(0, -5))) == (width: 60, height: 60))
        #expect(BoardLayout.size(of: sticky(size: square(10_000))) == (width: 480, height: 480))
        #expect(BoardLayout.size(of: sticky(size: size(200.4, 100.6))) == (width: 200, height: 101))
        #expect(BoardLayout.size(of: freeText(size: size(0, 10_000))) == (width: 100, height: 540))
    }

    @Test("As predefinições são quadradas, crescentes, dentro dos limites e incluem o tamanho padrão")
    func presets() {
        #expect(BoardLayout.stickyPresetSides == [80, 110, 160, 220])
        #expect(BoardLayout.freeTextPresetSides == [120, 180, 260, 360])
        let stickyDefault = BoardLayout.cardSize(for: .sticky).width
        let textDefault = BoardLayout.freeTextSide
        #expect(BoardLayout.stickyPresetSides.contains(stickyDefault) && BoardLayout.freeTextPresetSides.contains(textDefault))
        #expect(BoardLayout.stickyPresetSides == BoardLayout.stickyPresetSides.sorted())
        #expect(BoardLayout.freeTextPresetSides == BoardLayout.freeTextPresetSides.sorted())
        for side in BoardLayout.stickyPresetSides {
            // O padrão vira nil; as outras predefinições ficam como são, sem serem presas.
            #expect(BoardLayout.normalizedSize(square(side), for: .sticky) == (side == stickyDefault ? nil : square(side)))
        }
        for side in BoardLayout.freeTextPresetSides {
            #expect(BoardLayout.normalizedFreeTextSize(square(side)) == (side == textDefault ? nil : square(side)))
        }
    }

    // MARK: Contas de espaço

    @Test("A área ocupada e o retângulo delimitador contam o tamanho escolhido")
    func extentAndBoundsUseTheChosenSize() {
        let item = sticky(x: 100, y: 50, size: size(200, 160))
        #expect(BoardLayout.extent(of: [item]) == (width: 300, height: 210))
        #expect(BoardLayout.extent(of: [sticky(x: 100, y: 50)]) == (width: 210, height: 160), "controle: o padrão")

        let text = freeText(x: 10, y: 20, size: size(720, 540))
        #expect(BoardLayout.extent(of: [item], freeTexts: [text]) == (width: 730, height: 560))

        let bounds = BoardLayout.bounds(of: [sticky(x: 100, y: 50, size: size(300, 100))])
        #expect(bounds?.minX == 100 && bounds?.minY == 50 && bounds?.maxX == 400 && bounds?.maxY == 150)
        #expect(BoardLayout.center(of: [sticky(x: 100, y: 50, size: size(300, 100))]) == BoardPoint(x: 250, y: 100))
    }

    @Test("O acerto de um texto livre usa o tamanho dele")
    func freeTextHitTestUsesTheChosenSize() {
        let large = freeText(x: 100, y: 50, size: size(300, 200))
        #expect(BoardLayout.freeTextID(at: BoardPoint(x: 399, y: 249), among: [large]) == large.id)
        #expect(BoardLayout.freeTextID(at: BoardPoint(x: 400, y: 249), among: [large]) == nil)
        #expect(BoardLayout.freeTextID(at: BoardPoint(x: 399, y: 250), among: [large]) == nil)

        let small = freeText(x: 100, y: 50, size: size(100, 60))
        #expect(BoardLayout.freeTextID(at: BoardPoint(x: 199, y: 109), among: [small]) == small.id)
        #expect(BoardLayout.freeTextID(at: BoardPoint(x: 200, y: 109), among: [small]) == nil, "o quadrado padrão chegaria a 280")
        #expect(BoardLayout.freeTextID(at: BoardPoint(x: 150, y: 110), among: [small]) == nil)
    }

    @Test("A vaga de um cartão novo respeita o tamanho de quem já está no mural, e o cartão novo tem o tamanho padrão")
    func freePositionAvoidsTheRealSize() {
        let standard = sticky(x: 80, y: 80)
        let large = sticky(x: 80, y: 80, size: square(220))

        // A grade anda de 40 em 40 a partir de 80: o padrão libera a vaga em 214 (80 + 110 + 24), o grande só em 324 (80 + 220 + 24).
        #expect(BoardLayout.freePosition(for: .sticky, avoiding: [standard]) == BoardPoint(x: 240, y: 80), "controle: o padrão")
        #expect(BoardLayout.freePosition(for: .sticky, avoiding: [large]) == BoardPoint(x: 360, y: 80))
    }

    @Test("A vaga de um texto livre novo respeita o tamanho dos cartões e dos outros textos")
    func freeTextPositionAvoidsTheRealSize() {
        let largeSticky = sticky(x: 80, y: 80, size: square(480))
        let largeText = freeText(x: 700, y: 80, size: size(720, 540))
        let position = BoardLayout.freeTextPosition(avoiding: [largeSticky], freeTexts: [largeText])

        #expect(!overlapsWithGap(position, newSize: BoardLayout.freeTextSize, largeSticky))
        #expect(
            !BoardLayout.overlaps(
                position, BoardLayout.freeTextSize, largeText.position, BoardLayout.size(of: largeText), gap: 24))
    }

    @Test("A importação em lote desvia do tamanho real de quem já está no mural, com e sem ponto de partida")
    func importPositionsAvoidTheRealSize() {
        let large = sticky(x: 250, y: 250, size: square(220))
        let newSize = BoardLayout.cardSize(for: .sticky)

        let anchored = BoardLayout.importPositions(
            kinds: [.sticky, .sticky, .sticky], anchor: BoardPoint(x: 300, y: 300), avoiding: [large])
        #expect(anchored.count == 3)
        for position in anchored {
            #expect(!overlapsWithGap(position, newSize: newSize, large), "\(position) encosta no post-it grande")
        }

        let free = BoardLayout.importPositions(kinds: [.sticky, .sticky], anchor: nil, avoiding: [large])
        #expect(free.count == 2)
        for position in free {
            #expect(!overlapsWithGap(position, newSize: newSize, large), "\(position) encosta no post-it grande")
        }
    }

    @Test("O mosaico reserva o tamanho escolhido de cada cartão")
    func tilingUsesTheChosenSize() throws {
        let large = sticky("Grande", size: square(220), createdAt: 1)
        let small = sticky("Pequeno", createdAt: 2)
        let positions = BoardTiling.bsp([small, large], aspect: 1.6)

        #expect(try #require(positions[large.id]) == BoardPoint(x: 80, y: 80))
        #expect(try #require(positions[small.id]) == BoardPoint(x: 80 + 220 + 24, y: 80), "ao lado do grande, depois do vão")

        let alone = BoardTiling.bsp([large], aspect: 1.6)
        #expect(alone == [large.id: BoardPoint(x: 80, y: 80)])
    }

    @Test("A capa enquadra o mural com o tamanho escolhido de cartões e textos livres")
    func coverLayoutUsesTheChosenSize() {
        let near = sticky(x: 0, y: 0)
        let far = sticky(x: 2_000, y: 0, size: square(480))
        let wide = BoardCoverLayout.make(for: Board(items: [near, far]), coverWidth: 320, coverHeight: 200)
        #expect(isClose(wide.scale, 296.0 / 2_480.0), "o conteúdo vai de 0 a 2480 (2000 mais os 480 do post-it)")
        #expect(isClose(wide.coverOrigin.y, (200 - 480 * wide.scale) / 2))

        let text = freeText(x: 50, y: 70, size: size(720, 540))
        let large = BoardCoverLayout.make(for: Board(freeTexts: [text]), coverWidth: 320, coverHeight: 200)
        #expect(isClose(large.scale, 176.0 / 540.0))
        #expect(large.contentOrigin == BoardPoint(x: 50, y: 70))
        #expect(isClose(large.coverOrigin.x, (320 - 720 * large.scale) / 2))

        let standard = BoardCoverLayout.make(for: Board(freeTexts: [freeText(x: 50, y: 70)]), coverWidth: 320, coverHeight: 200)
        #expect(standard.scale == 0.6, "controle: sem tamanho, o quadrado de 180 cabe na escala máxima")
    }

    // MARK: Arrastar o canto

    @Test("Arrastar o canto soma o deslocamento ao tamanho atual do post-it")
    func resizedSizeAddsTheDrag() {
        #expect(BoardLayout.resizedSize(of: sticky(), deltaWidth: 50, deltaHeight: 30) == size(160, 140))
        #expect(BoardLayout.resizedSize(of: sticky(), deltaWidth: -20, deltaHeight: 0) == size(90, 110))
        #expect(BoardLayout.resizedSize(of: sticky(size: size(200, 150)), deltaWidth: 10, deltaHeight: -50) == size(210, 100))
        #expect(BoardLayout.resizedSize(of: sticky(), deltaWidth: 0, deltaHeight: 0) == square(110))
    }

    @Test("O tamanho arrastado é arredondado e preso aos limites")
    func resizedSizeIsRoundedAndClamped() {
        let item = sticky()
        #expect(BoardLayout.resizedSize(of: item, deltaWidth: 0.4, deltaHeight: -0.4) == square(110))
        #expect(BoardLayout.resizedSize(of: item, deltaWidth: 0.6, deltaHeight: 0.6) == square(111))
        #expect(BoardLayout.resizedSize(of: item, deltaWidth: 1_000, deltaHeight: 1_000) == square(480))
        #expect(BoardLayout.resizedSize(of: item, deltaWidth: -1_000, deltaHeight: -1_000) == square(60))
        #expect(BoardLayout.resizedSize(of: item, deltaWidth: 1_000, deltaHeight: -1_000) == size(480, 60))
    }

    @Test("Com a proporção mantida, o lado que mais anda manda e o outro o acompanha")
    func resizedSizeKeepsTheProportion() {
        let tall = sticky(size: size(100, 200))
        #expect(BoardLayout.resizedSize(of: tall, deltaWidth: 50, deltaHeight: 0, keepingProportion: true) == size(150, 300))
        #expect(BoardLayout.resizedSize(of: tall, deltaWidth: 5, deltaHeight: 20, keepingProportion: true) == size(110, 220))
        #expect(BoardLayout.resizedSize(of: tall, deltaWidth: -30, deltaHeight: -10, keepingProportion: true) == size(70, 140))
        #expect(
            BoardLayout.resizedSize(of: tall, deltaWidth: 50, deltaHeight: 0) == size(150, 200), "controle: sem Shift só a largura muda")
    }

    @Test("Com a proporção mantida, o limite de um lado para os dois juntos")
    func resizedSizeStopsBothSidesTogether() {
        let tall = sticky(size: size(100, 400))
        #expect(BoardLayout.resizedSize(of: tall, deltaWidth: 500, deltaHeight: 0, keepingProportion: true) == size(120, 480))
        let wide = sticky(size: size(100, 200))
        #expect(BoardLayout.resizedSize(of: wide, deltaWidth: -500, deltaHeight: -500, keepingProportion: true) == size(60, 120))
    }

    @Test("Um deslocamento inválido deixa o tamanho como está")
    func resizedSizeIgnoresInvalidDrag() {
        let item = sticky(size: size(200, 150))
        #expect(BoardLayout.resizedSize(of: item, deltaWidth: .nan, deltaHeight: 10) == size(200, 150))
        #expect(BoardLayout.resizedSize(of: item, deltaWidth: 10, deltaHeight: .infinity, keepingProportion: true) == size(200, 150))
    }

    @Test("Um cartão que não muda de tamanho continua com o tamanho atual")
    func resizedSizeOfNonResizableKind() {
        let photo = BoardItem(kind: .image, title: "Foto")
        let current = BoardLayout.cardSize(for: .image)
        #expect(BoardLayout.resizedSize(of: photo, deltaWidth: 100, deltaHeight: 100) == size(current.width, current.height))
    }

    @Test("O texto livre arrastado respeita os limites dele e a proporção")
    func resizedSizeOfFreeText() {
        let text = freeText()
        #expect(BoardLayout.resizedSize(of: text, deltaWidth: 100, deltaHeight: 0) == size(280, 180))
        #expect(BoardLayout.resizedSize(of: text, deltaWidth: 100, deltaHeight: 0, keepingProportion: true) == size(280, 280))
        #expect(BoardLayout.resizedSize(of: text, deltaWidth: 2_000, deltaHeight: 0) == size(720, 180))
        #expect(BoardLayout.resizedSize(of: text, deltaWidth: 2_000, deltaHeight: 0, keepingProportion: true) == size(540, 540))
        #expect(BoardLayout.resizedSize(of: text, deltaWidth: -500, deltaHeight: -500) == size(100, 60))
        #expect(BoardLayout.resizedSize(of: text, deltaWidth: -500, deltaHeight: -500, keepingProportion: true) == size(100, 100))
        #expect(BoardLayout.resizedSize(of: freeText(size: size(300, 200)), deltaWidth: 20, deltaHeight: 20) == size(320, 220))
    }

    // MARK: Escala do conteúdo

    @Test("A escala do conteúdo é a raiz da razão das áreas, presa entre 0,5 e 4")
    func contentScaleIsTheSquareRootOfTheAreaRatio() {
        func scale(_ width: Double, _ height: Double, from standard: Double = 110) -> Double {
            BoardLayout.contentScale(width: width, height: height, defaultWidth: standard, defaultHeight: standard)
        }
        #expect(scale(110, 110) == 1)
        #expect(isClose(scale(220, 220), 2))
        #expect(isClose(scale(110, 220), 2.0.squareRoot()))
        #expect(isClose(scale(60, 60), 60.0 / 110.0), "o menor post-it ainda fica acima do piso")
        #expect(scale(480, 480) == 4, "preso no teto")
        #expect(scale(10, 10) == 0.5, "preso no piso")
        #expect(isClose(scale(360, 360, from: 180), 2), "o texto livre usa o padrão dele")
    }

    @Test("Medidas inválidas dão escala 1")
    func contentScaleIgnoresInvalidMeasures() {
        #expect(BoardLayout.contentScale(width: 0, height: 100, defaultWidth: 110, defaultHeight: 110) == 1)
        #expect(BoardLayout.contentScale(width: 100, height: -1, defaultWidth: 110, defaultHeight: 110) == 1)
        #expect(BoardLayout.contentScale(width: .nan, height: 100, defaultWidth: 110, defaultHeight: 110) == 1)
        #expect(BoardLayout.contentScale(width: 100, height: 100, defaultWidth: 0, defaultHeight: 110) == 1)
        #expect(BoardLayout.contentScale(width: .infinity, height: 100, defaultWidth: 110, defaultHeight: 110) == 1)
    }

    // MARK: Modelo

    @Test("BoardModel grava o tamanho, reabre com ele e volta ao padrão")
    @MainActor
    func modelPersistsSizes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MuralResize-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(directory: directory)
        let model = BoardModel(store: store, seedIfEmpty: false)
        let note = model.createNote()
        let postIt = model.createSticky()
        let text = model.createFreeText("Anotação")

        #expect(model.resize(postIt.id, to: size(200.4, 5_000)))
        #expect(model.resizeFreeText(text.id, to: square(300)))
        #expect(model.item(id: postIt.id)?.size == size(200, 480), "o modelo grava o tamanho normalizado")
        #expect(model.freeText(id: text.id)?.size == square(300))

        let reopened = BoardModel(store: store, seedIfEmpty: false)
        #expect(reopened.item(id: postIt.id)?.size == size(200, 480))
        #expect(reopened.freeText(id: text.id)?.size == square(300))
        #expect(reopened.board.formatVersion == Self.requiredVersion)
        #expect(reopened.item(id: postIt.id)?.position == postIt.position, "o tamanho não muda o lugar")

        #expect(!model.resize(postIt.id, to: size(200, 480)), "o mesmo tamanho não é mudança")
        #expect(!model.resizeFreeText(text.id, to: square(300)))
        #expect(!model.resize(UUID(), to: square(200)))
        #expect(!model.resizeFreeText(UUID(), to: square(200)))
        #expect(!model.resize(note.id, to: square(200)), "nota não muda de tamanho")
        #expect(model.item(id: note.id)?.size == nil)

        #expect(model.resize(postIt.id, to: nil))
        #expect(model.resizeFreeText(text.id, to: square(180)), "o padrão tira o tamanho")
        let restored = BoardModel(store: store, seedIfEmpty: false)
        #expect(restored.item(id: postIt.id)?.size == nil)
        #expect(restored.freeText(id: text.id)?.size == nil)
        #expect(restored.board.formatVersion == 7, "sem tamanhos, só o texto livre exige a versão 7")
    }

    @Test("BoardModel com gravação adiada muda o tamanho em memória sem gravar")
    @MainActor
    func deferredModelDoesNotWrite() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MuralResize-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = sticky()
        let model = BoardModel(board: Board(items: [item]), store: BoardStore(directory: directory), persistence: .deferred)

        #expect(model.resize(item.id, to: square(160)))
        #expect(model.item(id: item.id)?.size == square(160))
        #expect(model.board.formatVersion == Self.requiredVersion)
        #expect(!FileManager.default.fileExists(atPath: directory.path), "a sessão é quem grava no modo adiado")
    }

    @Test("Um post-it redimensionado que sai da pasta procura uma vaga do tamanho dele")
    func resizedStickyLeavingAFolderFindsARoomyPlace() {
        // Entre os dois vizinhos cabe um post-it padrão, mas não um de 300 × 300.
        let left = sticky("Esquerda", x: 80, y: 80, createdAt: 1)
        let right = sticky("Direita", x: 400, y: 80, createdAt: 2)
        var big = sticky("Grande", size: square(300), createdAt: 3)
        big.parentID = UUID()
        let bigSize = BoardLayout.size(of: big)

        let standardSpot = BoardLayout.freePosition(for: .sticky, avoiding: [left, right])
        #expect(overlapsWithGap(standardSpot, newSize: bigSize, right), "controle: a vaga do post-it padrão não serve ao grande")

        let placed = BoardLayout.freePosition(for: big, avoiding: [left, right])
        #expect(!overlapsWithGap(placed, newSize: bigSize, left))
        #expect(!overlapsWithGap(placed, newSize: bigSize, right))
    }
}
