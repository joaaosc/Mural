import Foundation
import Testing

@testable import MuralKit

// MARK: Fixtures

/// Ids fixos e legíveis: `id(3)` é sempre o mesmo, e a ordem do `uuidString` segue a do número.
private func id(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012ld", number))!
}

/// A data de criação segue o número, a menos que o teste diga outra: quanto maior o número, mais novo o cartão.
private func date(_ seconds: Double) -> Date {
    Date(timeIntervalSince1970: seconds)
}

private func folder(_ number: Int, in parent: Int? = nil, at position: BoardPoint = .zero, created: Double? = nil) -> BoardItem {
    BoardItem(
        id: id(number), kind: .folder, title: "Pasta \(number)", createdAt: date(created ?? Double(number)),
        parentID: parent.map(id), position: position)
}

private func note(_ number: Int, in parent: Int? = nil, at position: BoardPoint = .zero, folderPosition: BoardPoint? = nil) -> BoardItem {
    BoardItem(
        id: id(number), kind: .text, title: "Nota \(number)", createdAt: date(Double(number)), parentID: parent.map(id),
        position: position, folderPosition: folderPosition)
}

private func sticky(_ number: Int, in parent: Int? = nil, at position: BoardPoint = .zero, folderPosition: BoardPoint? = nil) -> BoardItem {
    BoardItem(
        id: id(number), kind: .sticky, title: "Post-it \(number)", createdAt: date(Double(number)), parentID: parent.map(id),
        position: position, text: "Oi", folderPosition: folderPosition)
}

/// Pastas uma dentro da outra, a partir de `first`: a primeira solta no mural, a seguinte dentro dela, e assim por diante.
private func chain(_ levels: Int, from first: Int) -> [BoardItem] {
    (0..<levels).map { folder(first + $0, in: $0 == 0 ? nil : first + $0 - 1) }
}

/// O mural como uma build antiga o gravou (versão 0): só uma alteração de fato sobe a versão.
private func olderBoard(_ items: [BoardItem]) -> Board {
    var board = Board(items: items)
    board.formatVersion = 0
    return board
}

/// Toda cadeia de pais passa na regra do pacote portátil e todo lugar livre de pasta é de um post-it dentro de uma pasta.
private func isStructurallyValid(_ board: Board) -> Bool {
    let byID = Dictionary(uniqueKeysWithValues: board.items.map { ($0.id, $0) })
    return board.items.allSatisfy { item in
        Board.hasValidParentChain(item, in: byID) && (item.folderPosition == nil || item.isPlacedInFolder)
    }
}

/// Um mural com um pouco de tudo que dá errado quando duas pessoas mexem ao mesmo tempo, mais o que está certo. Os números dos
/// cartões são as datas de criação.
private func messyItems() -> [BoardItem] {
    [
        // Certo: o mural, uma pasta com conteúdo, um post-it com lugar livre.
        folder(1, at: BoardPoint(x: 80, y: 80)), note(2, at: BoardPoint(x: 300, y: 80)),
        folder(10, in: 1), note(11, in: 10), sticky(13, in: 10, folderPosition: BoardPoint(x: 20, y: 30)),
        // Lugar livre que não vale: post-it solto no mural e nota dentro de pasta.
        sticky(3, at: BoardPoint(x: 80, y: 300), folderPosition: BoardPoint(x: 5, y: 5)),
        note(12, in: 10, folderPosition: BoardPoint(x: 6, y: 6)),
        // Pai ausente, pai que não é pasta, e uma pasta órfã com conteúdo.
        note(20, in: 999), note(21, in: 2), folder(22, in: 2), note(23, in: 22),
        // Ciclo de três pastas, com uma nota presa nele.
        folder(30, in: 32), folder(31, in: 30), folder(32, in: 31), note(33, in: 31),
        // Nove pastas uma dentro da outra, com uma nota na última.
        folder(40), folder(41, in: 40), folder(42, in: 41), folder(43, in: 42), folder(44, in: 43), folder(45, in: 44),
        folder(46, in: 45), folder(47, in: 46), folder(48, in: 47), note(49, in: 48),
    ]
}

// MARK: Regra da cadeia de pais

@Suite("Cadeia de pais válida")
struct ParentChainRuleTests {
    private func isValid(_ item: BoardItem, in items: [BoardItem]) -> Bool {
        Board.hasValidParentChain(item, in: Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) }))
    }

    @Test("Cartão solto, ou dentro de pastas que chegam ao mural, tem cadeia válida")
    func validChains() {
        let levels = chain(Board.maximumFolderDepth, from: 1)
        let inLast = note(100, in: Board.maximumFolderDepth)
        let items = levels + [inLast, note(101)]
        #expect(items.allSatisfy { isValid($0, in: items) }, "o nível 8 e um cartão dentro dele cabem")
    }

    @Test("Pai ausente, pai que não é pasta, ciclo e pasta no nível 9 têm cadeia inválida")
    func invalidChains() {
        let orphan = note(1, in: 99)
        let underNote = note(3, in: 2)
        let parentNote = note(2)
        #expect(!isValid(orphan, in: [orphan]))
        #expect(!isValid(underNote, in: [parentNote, underNote]))

        let first = folder(4, in: 5)
        let second = folder(5, in: 4)
        #expect(!isValid(first, in: [first, second]))
        var selfParent = folder(6)
        selfParent.parentID = selfParent.id
        #expect(!isValid(selfParent, in: [selfParent]))

        let levels = chain(Board.maximumFolderDepth + 1, from: 10)
        #expect(!isValid(levels[Board.maximumFolderDepth], in: levels))
        #expect(isValid(levels[Board.maximumFolderDepth - 1], in: levels))
    }
}

// MARK: Conserto

@Suite("Conserto da estrutura do mural")
struct BoardStructureRepairTests {
    // MARK: Nada a consertar

    @Test("Mural válido não muda e devolve vazio, nem a versão do formato")
    func validBoardIsUntouched() {
        let levels = chain(Board.maximumFolderDepth, from: 20)
        let items = [
            folder(1, at: BoardPoint(x: 80, y: 80)), note(2, at: BoardPoint(x: 300, y: 80)), sticky(3, at: BoardPoint(x: 500, y: 80)),
            folder(4, in: 1), note(5, in: 4), sticky(6, in: 4, folderPosition: BoardPoint(x: 10, y: 20)), note(7, in: 1),
        ]
        var board = olderBoard(items + levels + [note(40, in: 20 + Board.maximumFolderDepth - 1)])
        let before = board
        #expect(isStructurallyValid(board), "controle: o mural de partida é válido")

        let moved = board.repairStructure()

        #expect(moved.isEmpty)
        #expect(board == before)
        #expect(board.formatVersion == 0)
    }

    @Test("Mural vazio não muda")
    func emptyBoardIsUntouched() {
        var board = Board()
        #expect(board.repairStructure().isEmpty)
        #expect(board == Board())
    }

    // MARK: Pai ausente ou que não é pasta

    @Test("Órfão vai para o mural, numa posição livre, sem mudar o lugar na lista")
    func orphanGoesToTheBoard() throws {
        let roots = [
            folder(1, at: BoardPoint(x: 80, y: 80)), note(2, at: BoardPoint(x: 80, y: 280)), note(3, at: BoardPoint(x: 300, y: 80)),
        ]
        let orphan = note(9, in: 99, at: BoardPoint(x: 5, y: 5))
        var board = olderBoard(roots + [orphan])

        let moved = board.repairStructure()

        #expect(moved == [orphan.id])
        let fixed = try #require(board.item(id: orphan.id))
        #expect(fixed.parentID == nil)
        #expect(fixed.position == BoardLayout.freePosition(for: .text, avoiding: roots))
        #expect(fixed.position != orphan.position)
        let size = BoardLayout.cardSize(for: .text)
        for other in roots {
            #expect(
                !BoardLayout.overlaps(fixed.position, size, other.position, BoardLayout.cardSize(for: other.kind), gap: 0),
                "cobre \(other.title)")
        }
        #expect(board.items.map(\.id) == (roots + [orphan]).map(\.id), "o lugar na lista não muda")
        #expect(board.formatVersion == board.requiredFormatVersion)
        #expect(isStructurallyValid(board))
    }

    @Test("Post-it redimensionado levado ao mural ganha uma vaga do tamanho que tem e não cobre os vizinhos")
    func resizedStickyGetsASpotOfItsOwnSize() throws {
        // O primeiro vão da grade, em (80, 80), cabe um post-it do tamanho padrão, mas não este.
        let roots = [note(2, at: BoardPoint(x: 240, y: 80))]
        var orphan = sticky(9, in: 99)
        orphan.size = BoardSize(width: 420, height: 300)
        var board = olderBoard(roots + [orphan])

        #expect(board.repairStructure() == [orphan.id])

        let fixed = try #require(board.item(id: orphan.id))
        #expect(fixed.position == BoardLayout.freePosition(for: orphan, avoiding: roots))
        for other in roots {
            #expect(
                !BoardLayout.overlaps(fixed.position, BoardLayout.size(of: fixed), other.position, BoardLayout.size(of: other), gap: 0),
                "cobre \(other.title)")
        }
    }

    @Test("O cartão levado ao mural não desvia da posição antiga que tinha dentro da pasta")
    func relocatedCardIgnoresItsOwnStalePosition() throws {
        let roots = [folder(1, at: BoardPoint(x: 80, y: 80))]
        let freeSpot = BoardLayout.freePosition(for: .text, avoiding: roots)
        let orphan = note(9, in: 99, at: freeSpot)
        var board = olderBoard(roots + [orphan])

        #expect(board.repairStructure() == [orphan.id])
        #expect(try #require(board.item(id: orphan.id)).position == freeSpot)
    }

    @Test("Pai que não é pasta leva o cartão para o mural, e uma pasta leva o que tem dentro")
    func parentThatIsNotAFolder() throws {
        let items = [
            note(1), note(2, in: 1), folder(3, in: 1), note(4, in: 3), sticky(5, in: 1, folderPosition: BoardPoint(x: 9, y: 9)),
        ]
        var board = olderBoard(items)

        let moved = board.repairStructure()

        #expect(moved == [id(2), id(3), id(5)])
        #expect(board.items.allSatisfy { $0.id == id(4) ? $0.parentID == id(3) : $0.parentID == nil })
        #expect(try #require(board.item(id: id(5))).folderPosition == nil, "o post-it perde o lugar livre da pasta")
        #expect(isStructurallyValid(board))
    }

    @Test("Vários órfãos ganham posições livres uns dos outros, do mais antigo ao mais novo")
    func severalOrphansAreSpreadOneAtATime() throws {
        let roots = [folder(1, at: BoardPoint(x: 80, y: 80))]
        // A ordem de criação (datas) não é a da lista nem a dos ids; o "D" empata a data com o "B" e perde pelo id.
        let orphans = [
            BoardItem(id: id(30), kind: .text, title: "C", createdAt: date(20), parentID: id(99)),
            BoardItem(id: id(10), kind: .image, title: "A", createdAt: date(30), parentID: id(98), fileName: "a.png"),
            BoardItem(id: id(40), kind: .link, title: "D", createdAt: date(10), parentID: id(96)),
            BoardItem(id: id(20), kind: .sticky, title: "B", createdAt: date(10), parentID: id(97), text: "Oi"),
        ]
        var board = olderBoard(roots + orphans)

        let moved = board.repairStructure()

        #expect(moved == [id(20), id(40), id(30), id(10)])
        // O mesmo que posicionar um de cada vez: cada um desvia dos que já estavam e dos que acabaram de ser posicionados.
        var placed = roots
        for movedID in moved {
            var expected = try #require(orphans.first { $0.id == movedID })
            expected.parentID = nil
            expected.position = BoardLayout.freePosition(for: expected.kind, avoiding: placed)
            #expect(try #require(board.item(id: movedID)) == expected)
            placed.append(expected)
        }
        #expect(isStructurallyValid(board))
    }

    // MARK: Ciclos

    @Test("Ciclo de duas pastas: sai a de menor id, mesmo sendo a mais nova, e o que está dentro continua dentro")
    func twoFolderCycle() throws {
        let smallest = folder(1, in: 2, created: 50)
        let other = folder(2, in: 1, created: 10)
        let inside = note(3, in: 2)
        var board = olderBoard([other, smallest, inside])

        let moved = board.repairStructure()

        #expect(moved == [smallest.id])
        #expect(try #require(board.item(id: id(1))).parentID == nil)
        #expect(try #require(board.item(id: id(2))).parentID == id(1))
        #expect(try #require(board.item(id: id(3))).parentID == id(2))
        #expect(isStructurallyValid(board))
    }

    @Test("Ciclo de três pastas: só a de menor id sai; a que está pendurada num membro fica onde está")
    func threeFolderCycle() throws {
        // A 5 está dentro da 7, a 7 dentro da 9 e a 9 dentro da 5; o menor id é o 5. A pasta 8 e a nota 4 estão penduradas no ciclo.
        let items = [folder(7, in: 9), folder(5, in: 7), folder(9, in: 5), folder(8, in: 9), note(4, in: 7)]
        var board = olderBoard(items)

        let moved = board.repairStructure()

        #expect(moved == [id(5)])
        let parents = Dictionary(uniqueKeysWithValues: board.items.map { ($0.id, $0.parentID) })
        #expect(parents[id(5)] == .some(nil))
        #expect(parents[id(9)] == id(5))
        #expect(parents[id(7)] == id(9))
        #expect(parents[id(8)] == id(9))
        #expect(parents[id(4)] == id(7))
        #expect(isStructurallyValid(board))
    }

    @Test("Pasta que é pai de si mesma vai para o mural")
    func selfParentFolder() throws {
        var selfParent = folder(1)
        selfParent.parentID = selfParent.id
        let child = note(2, in: 1)
        var board = olderBoard([selfParent, child])

        #expect(board.repairStructure() == [selfParent.id])
        #expect(try #require(board.item(id: selfParent.id)).parentID == nil)
        #expect(try #require(board.item(id: child.id)).parentID == selfParent.id)
    }

    @Test("Dois ciclos separados perdem uma pasta cada, na ordem de criação")
    func twoSeparateCycles() {
        let items = [
            folder(20, in: 21), folder(21, in: 20),  // menor id: 20
            folder(10, in: 11), folder(11, in: 10),  // menor id: 10
        ]
        var board = olderBoard(items)

        #expect(board.repairStructure() == [id(10), id(20)])
        #expect(isStructurallyValid(board))
    }

    // MARK: Profundidade

    @Test("Nove níveis: a pasta funda demais sobe para o mural com o que tem dentro")
    func ninthLevelGoesToTheBoard() throws {
        let levels = chain(Board.maximumFolderDepth + 1, from: 1)
        let inside = note(100, in: Board.maximumFolderDepth + 1)
        var board = olderBoard(levels + [inside])
        #expect(!isStructurallyValid(board), "controle: o nível 9 passa do limite")

        let moved = board.repairStructure()

        #expect(moved == [id(Board.maximumFolderDepth + 1)])
        let ninth = try #require(board.item(id: id(9)))
        #expect(ninth.parentID == nil)
        #expect(board.depth(of: ninth.id) == 0)
        #expect(try #require(board.item(id: inside.id)).parentID == ninth.id)
        for level in 2...Board.maximumFolderDepth {
            #expect(try #require(board.item(id: id(level))).parentID == id(level - 1), "o nível \(level) fica onde estava")
        }
        #expect(isStructurallyValid(board))
    }

    @Test("Dezessete níveis: sobem a pasta do nível 9 e, a partir dela, a do nível 9 de novo")
    func seventeenLevels() {
        var board = olderBoard(chain(2 * Board.maximumFolderDepth + 1, from: 1))

        #expect(board.repairStructure() == [id(9), id(17)])
        #expect(isStructurallyValid(board))
    }

    @Test("Ciclo com nove pastas: sai a de menor id e, sem o ciclo, a nona da cadeia também")
    func longCycleLosesTwoFolders() {
        // Cada pasta está dentro da anterior desta lista, e a primeira dentro da última. O menor id é o 11, no meio.
        let numbers = [14, 15, 16, 17, 11, 18, 19, 12, 13]
        let items = numbers.enumerated().map { position, number in
            folder(number, in: numbers[(position + numbers.count - 1) % numbers.count])
        }
        var board = olderBoard(items)

        // Sem o 11 no ciclo, a cadeia desce 11, 18, 19, 12, 13, 14, 15, 16, 17: a pasta 17 passa a ser o nível 9.
        #expect(board.repairStructure() == [id(11), id(17)])
        #expect(isStructurallyValid(board))
    }

    // MARK: Lugar livre na pasta

    @Test("Lugar livre solto é limpo sem contar como cartão levado ao mural")
    func strayFolderPositionIsCleared() throws {
        let valid = sticky(1, in: 10, folderPosition: BoardPoint(x: 10, y: 20))
        let items = [
            folder(10), valid, sticky(2, folderPosition: BoardPoint(x: 5, y: 5)), note(3, in: 10, folderPosition: BoardPoint(x: 6, y: 6)),
            note(4, folderPosition: BoardPoint(x: 7, y: 7)),
        ]
        var board = olderBoard(items)

        let moved = board.repairStructure()

        #expect(moved.isEmpty)
        #expect(try #require(board.item(id: valid.id)) == valid, "o post-it com lugar livre numa pasta continua igual")
        for number in [2, 3, 4] {
            #expect(try #require(board.item(id: id(number))).folderPosition == nil, "cartão \(number)")
        }
        // Só o lugar livre mudou: o resto de cada cartão e a pasta continuam como estavam.
        #expect(board.items.map(\.parentID) == items.map(\.parentID))
        #expect(board.items.map(\.position) == items.map(\.position))
        #expect(board.formatVersion == board.requiredFormatVersion)
        #expect(isStructurallyValid(board))
    }

    // MARK: Versão do formato

    @Test("Se algo mudou, a versão do formato passa a ser a exigida pelo conteúdo")
    func formatVersionFollowsTheContent() {
        var board = olderBoard([folder(1), folder(2, in: 1), note(3, in: 99)])
        #expect(board.formatVersion == 0)
        board.repairStructure()
        // A pasta dentro de pasta exige a versão 2.
        #expect(board.formatVersion == 2)
        #expect(board.formatVersion == board.requiredFormatVersion)
    }

    // MARK: Propriedades

    @Test("Consertar de novo não devolve nem muda nada")
    func repairingTwiceChangesNothing() {
        var board = olderBoard(messyItems())
        #expect(!isStructurallyValid(board), "controle: o mural de partida está quebrado")

        let first = board.repairStructure()
        let afterFirst = board
        let second = board.repairStructure()

        #expect(first == [id(20), id(21), id(22), id(30), id(48)])
        #expect(second.isEmpty)
        #expect(board == afterFirst)
        #expect(isStructurallyValid(board))
    }

    @Test("O que estava certo no mural quebrado continua como estava")
    func untouchedItemsStayTheSame() throws {
        let original = olderBoard(messyItems())
        var board = original
        let moved = Set(board.repairStructure())

        for item in original.items where !moved.contains(item.id) {
            var expected = item
            if item.id == id(3) || item.id == id(12) { expected.folderPosition = nil }
            #expect(try #require(board.item(id: item.id)) == expected, "cartão \(item.title)")
        }
        #expect(board.items.map(\.id) == original.items.map(\.id), "o lugar na lista não muda")
    }

    @Test("Duas cópias iguais chegam ao mesmo resultado, seja qual for a ordem da lista")
    func repairIsDeterministic() {
        let items = messyItems()
        var first = olderBoard(items)
        var second = olderBoard(items)
        var reversed = olderBoard(items.reversed())
        var rotated = olderBoard(Array(items[7...] + items[..<7]))

        let movedFirst = first.repairStructure()
        let movedSecond = second.repairStructure()
        let movedReversed = reversed.repairStructure()
        let movedRotated = rotated.repairStructure()

        #expect(first == second)
        #expect(movedFirst == movedSecond)
        #expect(movedFirst == movedReversed && movedFirst == movedRotated)
        let byID = Dictionary(uniqueKeysWithValues: first.items.map { ($0.id, $0) })
        for other in [reversed, rotated] {
            #expect(Dictionary(uniqueKeysWithValues: other.items.map { ($0.id, $0) }) == byID)
        }
    }

    @Test("Cartão com id repetido conta só na primeira vez e não derruba o conserto")
    func repeatedIDsDoNotCrash() {
        let first = note(1, in: 99)
        var duplicate = note(1)
        duplicate.title = "Repetido"
        var board = olderBoard([first, duplicate, folder(2)])

        #expect(board.repairStructure() == [first.id])
        #expect(board.items[0].parentID == nil)
        #expect(board.items[1] == duplicate, "a repetição não é tocada")
        #expect(board.repairStructure().isEmpty)
    }

    // MARK: Pacote portátil

    @Test("O mural consertado passa na validação do pacote; o quebrado não passa")
    func repairedBoardPassesThePackageValidation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MuralRepair-\(UUID().uuidString)", isDirectory: true)
        let items = root.appendingPathComponent("Items", isDirectory: true)
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = BoardPortablePackageService(availableCapacity: { _ in nil })

        let broken = olderBoard(messyItems())
        await #expect(throws: BoardPortablePackageError.self) {
            try await service.validateBoard(broken, itemsURL: items)
        }
        var repaired = broken
        repaired.repairStructure()
        try await service.validateBoard(repaired, itemsURL: items)
    }
}
