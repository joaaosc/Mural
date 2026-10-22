import Foundation
import Testing

@testable import MuralKit

// MARK: Fixtures

/// Datas explícitas: a ordem dos filhos vem da criação, e dois `Date.now` seguidos podem empatar.
private func date(_ seconds: Double) -> Date {
    Date(timeIntervalSince1970: seconds)
}

private func folder(
    _ title: String, in parent: BoardItem? = nil, at seconds: Double = 0, position: BoardPoint = .zero
) -> BoardItem {
    BoardItem(kind: .folder, title: title, createdAt: date(seconds), parentID: parent?.id, position: position)
}

private func note(_ title: String, in parent: BoardItem? = nil, at seconds: Double = 0) -> BoardItem {
    BoardItem(kind: .text, title: title, createdAt: date(seconds), parentID: parent?.id)
}

/// Pastas uma dentro da outra: "Nível 1" solta no mural, "Nível 2" dentro dela, e assim por diante.
private func folderChain(_ levels: Int) -> [BoardItem] {
    var chain: [BoardItem] = []
    for level in 1...levels {
        chain.append(folder("Nível \(level)", in: chain.last, at: Double(level)))
    }
    return chain
}

/// O mural como uma build antiga o gravou (versão 0): só uma alteração de fato sobe a versão.
private func olderBoard(_ items: [BoardItem]) -> Board {
    var board = Board(items: items)
    board.formatVersion = 0
    return board
}

/// A ⊃ B ⊃ C, com uma nota em B e outra em C; a pasta "Outra" e uma nota soltas no mural.
private struct NestedTree {
    let a = folder("A", at: 1)
    let b: BoardItem
    let c: BoardItem
    let noteInB: BoardItem
    let noteInC: BoardItem
    let other = folder("Outra", at: 6, position: BoardPoint(x: 400, y: 40))
    let loose = note("Solta", at: 7)

    init() {
        b = folder("B", in: a, at: 2)
        c = folder("C", in: b, at: 3)
        noteInB = note("Em B", in: b, at: 4)
        noteInC = note("Em C", in: c, at: 5)
    }

    var board: Board { Board(items: [a, b, c, noteInB, noteInC, other, loose]) }
}

// MARK: Domínio

@Suite("Pasta dentro de pasta")
struct NestedFolderTests {
    private let tree = NestedTree()

    @Test("O formato com pasta dentro de pasta é a versão 2, e o limite é de 8 níveis")
    func formatVersionAndLimit() {
        #expect(Board.currentFormatVersion >= 2)
        #expect(Board().formatVersion == 1, "mural sem pasta aninhada continua na versão 1")
        #expect(tree.board.formatVersion == 2)
        #expect(Board.maximumFolderDepth == 8)
    }

    // MARK: Mover

    @Test("Pasta solta entra em outra pasta, com o que há dentro, sem mexer na posição nem na ordem")
    func movesFolderIntoFolder() {
        var board = olderBoard(tree.board.items)
        let moved = board.moveIntoFolder(id: tree.other.id, folderID: tree.c.id)
        #expect(moved)
        var expected = tree.other
        expected.parentID = tree.c.id
        #expect(board.item(id: tree.other.id) == expected)
        #expect(board.items.map(\.id) == tree.board.items.map(\.id))
        #expect(board.children(of: tree.c.id).map(\.id) == [tree.noteInC.id, tree.other.id])
        #expect(board.depth(of: tree.other.id) == 3)
        #expect(board.formatVersion == 2)

        // Uma pasta com conteúdo leva o conteúdo junto.
        var withContent = tree.board
        let movedWithContent = withContent.moveIntoFolder(id: tree.b.id, folderID: tree.other.id)
        #expect(movedWithContent)
        #expect(withContent.children(of: tree.other.id).map(\.id) == [tree.b.id])
        #expect(withContent.children(of: tree.b.id).map(\.id) == [tree.c.id, tree.noteInB.id])
        #expect(withContent.ancestors(of: tree.noteInC.id).map(\.id) == [tree.c.id, tree.b.id, tree.other.id])
    }

    @Test("Cartão de uma pasta vai direto para outra pasta, em qualquer nível")
    func movesCardBetweenFolders() {
        var board = tree.board
        let movedUp = board.moveIntoFolder(id: tree.noteInC.id, folderID: tree.a.id)
        #expect(movedUp)
        #expect(board.children(of: tree.c.id).isEmpty)
        #expect(board.children(of: tree.a.id).map(\.id) == [tree.b.id, tree.noteInC.id])
        #expect(board.depth(of: tree.noteInC.id) == 1)
        let movedBack = board.moveIntoFolder(id: tree.noteInC.id, folderID: tree.c.id)
        #expect(movedBack)
        #expect(board.depth(of: tree.noteInC.id) == 3)
        #expect(board.items.map(\.id) == tree.board.items.map(\.id))
    }

    @Test("Recusa o ciclo: A em B depois de B em A, e A em qualquer pasta que esteja dentro de A")
    func refusesCycles() {
        let first = folder("Primeira", at: 1)
        let second = folder("Segunda", at: 2)
        var board = Board(items: [first, second])
        let firstInSecond = board.moveIntoFolder(id: first.id, folderID: second.id)
        #expect(firstInSecond)
        let afterFirst = board
        let secondInFirst = board.moveIntoFolder(id: second.id, folderID: first.id)
        #expect(!secondInFirst)
        #expect(board == afterFirst)

        // A ⊃ B ⊃ C: A não vai para o filho nem para o neto.
        let nested = olderBoard(tree.board.items)
        for destination in [tree.b, tree.c] {
            var attempt = nested
            let accepted = attempt.moveIntoFolder(id: tree.a.id, folderID: destination.id)
            #expect(!accepted, "A entrou em \(destination.title)")
            #expect(attempt == nested, "alterou o mural ao levar A para \(destination.title)")
        }
    }

    @Test("Recusa o que não pode entrar, sem alterar o mural nem a versão do formato")
    func refusesInvalidMoves() {
        let cases: [(name: String, id: UUID, folderID: UUID)] = [
            ("o próprio id", tree.a.id, tree.a.id),
            ("destino que não é pasta", tree.loose.id, tree.noteInB.id),
            ("destino que já é o pai", tree.noteInB.id, tree.b.id),
            ("pasta que já está no destino", tree.c.id, tree.b.id),
            ("cartão desconhecido", UUID(), tree.a.id),
            ("pasta desconhecida", tree.loose.id, UUID()),
            ("os dois desconhecidos", UUID(), UUID()),
        ]
        let board = olderBoard(tree.board.items)
        for refusal in cases {
            var attempt = board
            let accepted = attempt.moveIntoFolder(id: refusal.id, folderID: refusal.folderID)
            #expect(!accepted, "aceitou \(refusal.name)")
            #expect(attempt == board, "alterou o mural em \(refusal.name)")
        }
    }

    @Test("Pasta só entra onde ela e as subpastas dela ainda cabem nos 8 níveis; cartão cabe em qualquer pasta")
    func foldersStopAtTheLimit() {
        let chain = folderChain(Board.maximumFolderDepth)
        let pair = folder("Par", at: 20)
        let inPair = folder("No par", in: pair, at: 21)
        let single = folder("Sozinha", at: 22)
        let card = note("Cartão", at: 23)
        let base = olderBoard(chain + [pair, inPair, single, card])
        let cases: [(name: String, id: UUID, destination: BoardItem, accepted: Bool)] = [
            ("pasta com uma subpasta no nível 6 (6 + 2 = 8)", pair.id, chain[5], true),
            ("pasta com uma subpasta no nível 7 (7 + 2 = 9)", pair.id, chain[6], false),
            ("pasta sem subpastas no nível 7 (7 + 1 = 8)", single.id, chain[6], true),
            ("pasta sem subpastas no nível 8 (8 + 1 = 9)", single.id, chain[7], false),
            ("cartão que não é pasta no nível 8", card.id, chain[7], true),
        ]
        for move in cases {
            var attempt = base
            let accepted = attempt.moveIntoFolder(id: move.id, folderID: move.destination.id)
            #expect(accepted == move.accepted, "\(move.name)")
            #expect((attempt == base) == !move.accepted, "\(move.name): o mural \(accepted ? "deveria" : "não deveria") ter mudado")
        }
    }

    // MARK: Remover

    @Test("Remover uma pasta leva todos os níveis, devolve na ordem da lista e deixa o resto")
    func removeIsRecursive() {
        // Ordem da lista propositalmente diferente da hierarquia.
        let items = [tree.noteInC, tree.loose, tree.b, tree.a, tree.other, tree.c, tree.noteInB]

        var board = olderBoard(items)
        let removed = board.remove(id: tree.a.id)
        #expect(removed.map(\.id) == [tree.noteInC.id, tree.b.id, tree.a.id, tree.c.id, tree.noteInB.id])
        #expect(board.items.map(\.id) == [tree.loose.id, tree.other.id])
        #expect(board.formatVersion == 1, "sem a pasta aninhada, o resto volta à versão 1")

        var middle = olderBoard(items)
        let removedFromMiddle = middle.remove(id: tree.b.id)
        #expect(removedFromMiddle.map(\.id) == [tree.noteInC.id, tree.b.id, tree.c.id, tree.noteInB.id])
        #expect(middle.items.map(\.id) == [tree.loose.id, tree.a.id, tree.other.id])

        var leaf = olderBoard(items)
        let removedLeaf = leaf.remove(id: tree.noteInC.id)
        #expect(removedLeaf.map(\.id) == [tree.noteInC.id])
        #expect(leaf.items.count == items.count - 1)

        var unknown = olderBoard(items)
        let removedUnknown = unknown.remove(id: UUID())
        #expect(removedUnknown.isEmpty)
        #expect(unknown == olderBoard(items))
    }

    // MARK: Hierarquia

    @Test("Ancestrais vão da pasta mais próxima à solta no mural, e a profundidade conta as pastas acima")
    func ancestorsAndDepth() {
        let board = tree.board
        #expect(board.ancestors(of: tree.noteInC.id).map(\.id) == [tree.c.id, tree.b.id, tree.a.id])
        #expect(board.ancestors(of: tree.c.id).map(\.id) == [tree.b.id, tree.a.id])
        #expect(board.ancestors(of: tree.a.id).isEmpty)
        #expect(board.ancestors(of: tree.loose.id).isEmpty)
        #expect(board.ancestors(of: UUID()).isEmpty)
        #expect(board.depth(of: tree.noteInC.id) == 3)
        #expect(board.depth(of: tree.c.id) == 2)
        #expect(board.depth(of: tree.a.id) == 0)
        #expect(board.depth(of: UUID()) == 0)
    }

    @Test("Ancestrais param no pai ausente ou que não é pasta")
    func ancestorsStopAtBrokenLinks() {
        let orphan = BoardItem(kind: .text, title: "Órfão", parentID: UUID())
        let parentCard = BoardItem(kind: .text, title: "Cartão com filho", parentID: tree.a.id)
        let child = BoardItem(kind: .text, title: "Filho de cartão", parentID: parentCard.id)
        let board = Board(items: [tree.a, orphan, parentCard, child])
        #expect(board.ancestors(of: orphan.id).isEmpty)
        #expect(board.ancestors(of: child.id).isEmpty)
        #expect(board.ancestors(of: parentCard.id).map(\.id) == [tree.a.id])
    }

    @Test("Descendentes vêm nível a nível e, dentro de cada pasta, na ordem de criação")
    func descendantsAreByLevel() {
        let root = folder("Raiz", at: 1)
        let sub = folder("Sub", in: root, at: 2)
        let direct = note("Direto", in: root, at: 3)
        let inSub = note("Em Sub", in: sub, at: 4)
        let deep = folder("Funda", in: sub, at: 5)
        let inDeep = note("Em Funda", in: deep, at: 6)
        let board = Board(items: [inDeep, direct, root, deep, inSub, sub])
        #expect(board.descendants(of: root.id).map(\.id) == [sub.id, direct.id, inSub.id, deep.id, inDeep.id])
        #expect(board.descendants(of: sub.id).map(\.id) == [inSub.id, deep.id, inDeep.id])
        #expect(board.descendants(of: inDeep.id).isEmpty)
        #expect(board.descendants(of: UUID()).isEmpty)
    }

    @Test("Dado corrompido com ciclo: ancestrais, descendentes, profundidade, remoção e destinos terminam")
    func cyclesTerminate() {
        let firstID = UUID()
        let secondID = UUID()
        let first = BoardItem(id: firstID, kind: .folder, title: "Primeira", createdAt: date(1), parentID: secondID)
        let second = BoardItem(id: secondID, kind: .folder, title: "Segunda", createdAt: date(2), parentID: firstID)
        let inside = note("Dentro", in: second, at: 3)
        var selfParent = folder("Própria mãe", at: 4)
        selfParent.parentID = selfParent.id
        let root = folder("Raiz", at: 5)
        let board = Board(items: [first, second, inside, selfParent, root])

        #expect(board.ancestors(of: inside.id).map(\.id) == [secondID, firstID])
        #expect(board.depth(of: inside.id) == 2)
        #expect(board.descendants(of: firstID).map(\.id) == [secondID, inside.id])
        #expect(board.ancestors(of: selfParent.id).isEmpty)
        #expect(board.descendants(of: selfParent.id).isEmpty)
        // Só as pastas que se alcança a partir do mural são destinos.
        #expect(board.folderDestinations(for: inside.id).map(\.id) == [root.id])

        var removal = board
        let removedCycle = removal.remove(id: firstID)
        #expect(removedCycle.map(\.id) == [firstID, secondID, inside.id])
        #expect(removal.items.map(\.id) == [selfParent.id, root.id])
        var selfRemoval = board
        let removedSelfParent = selfRemoval.remove(id: selfParent.id)
        #expect(removedSelfParent.map(\.id) == [selfParent.id])

        var attempt = board
        let intoItself = attempt.moveIntoFolder(id: firstID, folderID: firstID)
        #expect(!intoItself)
        let outOfTheCycle = attempt.moveIntoFolder(id: inside.id, folderID: root.id)
        #expect(outOfTheCycle)
    }

    // MARK: Destinos

    @Test("Destinos mostram o caminho de títulos, seguem a ordem do Finder e deixam de fora os que não servem")
    func folderDestinations() {
        let archive = folder("Arquivo", at: 1)
        let house = folder("Casa", at: 2)
        let bedroom = folder("Quarto", in: house, at: 3)
        let wardrobe = folder("Armário", in: bedroom, at: 4)
        let kitchen = folder("Cozinha", in: house, at: 5)
        let trip = folder("Viagem", at: 6)
        let card = note("Cartão", at: 7)
        let inBedroom = note("No quarto", in: bedroom, at: 8)
        let board = Board(items: [trip, card, wardrobe, inBedroom, bedroom, kitchen, house, archive])

        // Cartão solto: todas as pastas, em qualquer nível.
        let all = board.folderDestinations(for: card.id)
        #expect(
            all.map(\.title) == ["Arquivo", "Casa", "Casa › Cozinha", "Casa › Quarto", "Casa › Quarto › Armário", "Viagem"])
        #expect(all.contains(FolderDestination(id: wardrobe.id, path: ["Casa", "Quarto", "Armário"])))
        #expect(all.first { $0.id == wardrobe.id }?.title == "Casa › Quarto › Armário")

        // Cartão numa pasta: a pasta onde já está não é oferecida.
        #expect(
            board.folderDestinations(for: inBedroom.id).map(\.title)
                == ["Arquivo", "Casa", "Casa › Cozinha", "Casa › Quarto › Armário", "Viagem"])

        // Pasta: sem ela, sem o que há dentro dela e sem a pasta onde já está.
        #expect(board.folderDestinations(for: bedroom.id).map(\.title) == ["Arquivo", "Casa › Cozinha", "Viagem"])
        #expect(board.folderDestinations(for: wardrobe.id).map(\.title) == ["Arquivo", "Casa", "Casa › Cozinha", "Viagem"])
        #expect(board.folderDestinations(for: house.id).map(\.title) == ["Arquivo", "Viagem"])

        #expect(board.folderDestinations(for: UUID()).isEmpty)
    }

    @Test("Destinos seguem a ordem do Finder: sem diferenciar maiúsculas e com os números por valor")
    func destinationsUseFinderOrder() {
        let card = note("Cartão", at: 4)
        let board = Board(items: [folder("Pasta 10", at: 1), folder("pasta 2", at: 2), folder("Pasta 1", at: 3), card])
        #expect(board.folderDestinations(for: card.id).map(\.title) == ["Pasta 1", "pasta 2", "Pasta 10"])
    }

    @Test("Pastas com o mesmo nome aparecem as duas, sempre na mesma ordem")
    func equalTitlesAreStable() {
        let first = folder("Nova pasta", at: 1)
        let second = folder("Nova pasta", at: 2)
        let card = note("Cartão", at: 3)
        let board = Board(items: [first, second, card])
        for _ in 0..<5 {
            #expect(board.folderDestinations(for: card.id).map(\.id) == [first.id, second.id])
        }
    }

    @Test("Destinos de uma pasta cortam os níveis em que ela e as subpastas dela não cabem")
    func destinationsRespectTheLimit() {
        let chain = folderChain(Board.maximumFolderDepth)
        let mover = folder("Com filha", at: 20)
        let moverChild = folder("Filha", in: mover, at: 21)
        let card = note("Cartão", at: 22)
        let board = Board(items: chain + [mover, moverChild, card])

        // Uma pasta com uma subpasta ocupa 2 níveis: cabe só debaixo dos níveis 1 a 6.
        #expect(Set(board.folderDestinations(for: mover.id).map(\.id)) == Set(chain.prefix(6).map(\.id)))
        // Cartão que não é pasta cabe em qualquer pasta, até na do nível 8.
        #expect(Set(board.folderDestinations(for: card.id).map(\.id)) == Set((chain + [mover, moverChild]).map(\.id)))
    }
}

// MARK: Modelo

@MainActor
@Suite("Pasta dentro de pasta no modelo")
struct NestedFolderModelTests {
    private func makeStore() -> BoardStore {
        BoardStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("MuralNested-\(UUID().uuidString)"))
    }

    private func makeModel(store: BoardStore) -> BoardModel {
        BoardModel(store: store, seedIfEmpty: false)
    }

    /// Com uma pasta no lugar do board.json, qualquer gravação falharia e preencheria `lastError`.
    private func breakPersistence(of store: BoardStore) throws {
        try FileManager.default.removeItem(at: store.fileURL)
        try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: true)
    }

    @Test("Pasta nova dentro de pasta fica no pai, com o nome sem espaços nas pontas, e é gravada")
    func createsFolderInsideFolder() throws {
        let store = makeStore()
        let model = makeModel(store: store)
        let parent = model.createFolder(named: "Casa")
        let child = try #require(model.createFolder(named: "  Quarto  ", into: parent.id))
        #expect(child.kind == .folder)
        #expect(child.title == "Quarto")
        #expect(child.parentID == parent.id)
        #expect(model.rootItems.map(\.id) == [parent.id])
        #expect(model.children(of: parent.id).map(\.id) == [child.id])
        #expect(try #require(model.createFolder(named: " \n ", into: child.id)).title == "Nova pasta")

        let reopened = makeModel(store: store)
        #expect(reopened.item(id: child.id)?.parentID == parent.id)
    }

    @Test("Pasta nova só cabe em pasta que existe e que ainda não está no último nível")
    func folderCreationStopsAtTheLimit() throws {
        let store = makeStore()
        let model = makeModel(store: store)
        let card = model.createNote()
        var parent = model.createFolder(named: "Nível 1")
        for level in 2...Board.maximumFolderDepth {
            #expect(model.canCreateFolder(in: parent.id), "o nível \(level - 1) deveria aceitar uma pasta")
            parent = try #require(model.createFolder(named: "Nível \(level)", into: parent.id))
        }
        #expect(model.board.depth(of: parent.id) == Board.maximumFolderDepth - 1)
        let before = model.board
        try breakPersistence(of: store)

        #expect(model.canCreateFolder(in: nil))
        #expect(!model.canCreateFolder(in: parent.id), "o nível 8 já é o último")
        #expect(model.createFolder(named: "Nível 9", into: parent.id) == nil)
        #expect(!model.canCreateFolder(in: card.id))
        #expect(model.createFolder(named: "Dentro de cartão", into: card.id) == nil)
        #expect(!model.canCreateFolder(in: UUID()))
        #expect(model.createFolder(named: "Dentro de nada", into: UUID()) == nil)
        #expect(model.board == before)
        #expect(model.lastError == nil, "nada deveria ter sido gravado")

        // O mural continua aceitando pastas soltas.
        model.createFolder(named: "Solta")
        #expect(model.lastError != nil, "controle: criar uma pasta tenta gravar")
    }

    @Test("Subir leva o cartão para a pasta de cima e, se a pasta está solta, para o mural")
    func moveUpOneLevelAtATime() throws {
        let store = makeStore()
        let model = makeModel(store: store)
        let outer = model.createFolder(named: "Externa")
        let inner = try #require(model.createFolder(named: "Interna", into: outer.id))
        let card = model.createNote(into: inner.id)

        model.moveUp(card.id)
        #expect(model.item(id: card.id)?.parentID == outer.id)
        #expect(BoardModel(store: store, seedIfEmpty: false).item(id: card.id)?.parentID == outer.id)

        model.moveUp(card.id)
        #expect(model.item(id: card.id)?.parentID == nil)
        #expect(model.board.items.last?.id == card.id)
        #expect(BoardModel(store: store, seedIfEmpty: false).item(id: card.id)?.parentID == nil)
        #expect(model.lastError == nil)
    }

    @Test("Subir uma pasta leva o conteúdo dela junto")
    func moveUpCarriesFolderContent() throws {
        let model = makeModel(store: makeStore())
        let outer = model.createFolder(named: "Externa")
        let inner = try #require(model.createFolder(named: "Interna", into: outer.id))
        let deep = try #require(model.createFolder(named: "Funda", into: inner.id))
        let inDeep = model.createNote(into: deep.id)

        model.moveUp(deep.id)
        #expect(model.item(id: deep.id)?.parentID == outer.id)
        #expect(model.item(id: inDeep.id)?.parentID == deep.id)

        model.moveUp(deep.id)
        #expect(model.item(id: deep.id)?.parentID == nil)
        #expect(model.item(id: inDeep.id)?.parentID == deep.id)
        #expect(model.board.ancestors(of: inDeep.id).map(\.id) == [deep.id])
    }

    @Test("Subir um cartão que já está solto, ou desconhecido, não muda nem grava nada")
    func moveUpOfLooseCardDoesNothing() throws {
        let store = makeStore()
        let model = makeModel(store: store)
        let loose = model.createNote()
        let before = model.board
        try breakPersistence(of: store)

        model.moveUp(loose.id)
        model.moveUp(UUID())
        #expect(model.board == before)
        #expect(model.lastError == nil)

        model.move(loose.id, to: BoardPoint(x: 10, y: 10))
        #expect(model.lastError != nil, "controle: um movimento válido tenta gravar")
    }

    @Test("Conta os cartões de todos os níveis dentro da pasta")
    func descendantCountCoversEveryLevel() throws {
        let model = makeModel(store: makeStore())
        let outer = model.createFolder(named: "Externa")
        let inner = try #require(model.createFolder(named: "Interna", into: outer.id))
        model.createNote(into: outer.id)
        model.createNote(into: inner.id)
        model.createSticky(into: inner.id)
        #expect(model.descendantCount(of: outer.id) == 4)
        #expect(model.descendantCount(of: inner.id) == 2)
        #expect(model.descendantCount(of: model.createNote().id) == 0)
        #expect(model.descendantCount(of: UUID()) == 0)
    }

    @Test("Apagar uma pasta apaga os arquivos de todos os níveis e mantém os de fora")
    func deleteRemovesFilesOfEveryLevel() throws {
        let store = makeStore()
        let model = makeModel(store: store)
        let outer = model.createFolder(named: "Externa")
        let inner = try #require(model.createFolder(named: "Interna", into: outer.id))
        let first = try #require(model.importData(Data([1]), fileExtension: "mov", kind: .video, title: "Clipe 1", into: outer.id))
        let second = try #require(model.importData(Data([2]), fileExtension: "mov", kind: .video, title: "Clipe 2", into: inner.id))
        let outside = try #require(model.importData(Data([3]), fileExtension: "mov", kind: .video, title: "Clipe de fora"))
        let firstFile = try #require(model.fileURL(for: first))
        let secondFile = try #require(model.fileURL(for: second))
        let outsideFile = try #require(model.fileURL(for: outside))
        #expect([firstFile, secondFile, outsideFile].allSatisfy { FileManager.default.fileExists(atPath: $0.path) })

        model.delete(outer.id)
        #expect(model.lastError == nil)
        #expect([outer, inner, first, second].allSatisfy { model.item(id: $0.id) == nil })
        #expect(!FileManager.default.fileExists(atPath: firstFile.path))
        #expect(!FileManager.default.fileExists(atPath: secondFile.path))
        #expect(FileManager.default.fileExists(atPath: outsideFile.path))

        let reopened = makeModel(store: store)
        #expect(reopened.item(id: inner.id) == nil)
        #expect(reopened.item(id: outside.id) != nil)
    }
}

// MARK: Estado de navegação

@Suite("Pasta dentro de pasta no estado de navegação")
struct NestedFolderWorkspaceTests {
    private let tree = NestedTree()

    @Test("Caminho de três níveis de pasta e uma página de cartão é válido")
    func deepPathIsValid() {
        let path: [WorkspaceDestination] = [
            .collection(tree.a.id), .collection(tree.b.id), .collection(tree.c.id), .item(tree.noteInC.id),
        ]
        let result = BoardWorkspaceState(path: path).canonicalized(for: tree.board)
        #expect(result.state.path == path)
        #expect(result.issues.isEmpty)
    }

    @Test("O caminho aceita 8 pastas e uma página; o que passa disso é cortado")
    func pathStopsAtTheLimit() {
        let chain = folderChain(Board.maximumFolderDepth)
        let page = note("Na última", in: chain.last, at: 30)
        let extra = note("Passa do limite", in: chain.last, at: 31)
        let board = Board(items: chain + [page, extra])
        let full = chain.map { WorkspaceDestination.collection($0.id) } + [.item(page.id)]
        #expect(full.count == Board.maximumFolderDepth + 1)

        let valid = BoardWorkspaceState(path: full).canonicalized(for: board)
        #expect(valid.state.path == full)
        #expect(valid.issues.isEmpty)

        let tooLong = BoardWorkspaceState(path: full + [.item(extra.id)]).canonicalized(for: board)
        #expect(tooLong.state.path == full)
        #expect(tooLong.issues == [.pathTruncated(index: Board.maximumFolderDepth + 1)])
    }

    @Test("Cadeia de pais errada corta o caminho no primeiro destino ruim")
    func wrongParentChainIsTruncated() {
        let board = tree.board
        // C não está direto em A: o caminho pula B.
        let skipped = BoardWorkspaceState(path: [.collection(tree.a.id), .collection(tree.c.id), .item(tree.noteInC.id)])
            .canonicalized(for: board)
        #expect(skipped.state.path == [.collection(tree.a.id)])
        #expect(skipped.issues == [.invalidPath(index: 1), .pathTruncated(index: 1)])

        // O primeiro destino só pode ser uma pasta solta no mural.
        let fromTheMiddle = BoardWorkspaceState(path: [.collection(tree.b.id)]).canonicalized(for: board)
        #expect(fromTheMiddle.state.path.isEmpty)
        #expect(fromTheMiddle.issues == [.invalidPath(index: 0), .pathTruncated(index: 0)])

        // A nota é de C, não de B.
        let wrongPage = BoardWorkspaceState(path: [.collection(tree.a.id), .collection(tree.b.id), .item(tree.noteInC.id)])
            .canonicalized(for: board)
        #expect(wrongPage.state.path == [.collection(tree.a.id), .collection(tree.b.id)])
        #expect(wrongPage.issues == [.invalidPath(index: 2), .pathTruncated(index: 2)])

        // Pasta no lugar de página, e página no lugar de pasta.
        let wrongKind = BoardWorkspaceState(path: [.item(tree.a.id)]).canonicalized(for: board)
        #expect(wrongKind.state.path.isEmpty)
        let wrongCollection = BoardWorkspaceState(path: [.collection(tree.a.id), .collection(tree.noteInB.id)])
            .canonicalized(for: board)
        #expect(wrongCollection.state.path == [.collection(tree.a.id)])
    }

    @Test("Nada vem depois de uma página de cartão")
    func nothingFollowsAnItemPage() {
        let path: [WorkspaceDestination] = [
            .collection(tree.a.id), .collection(tree.b.id), .item(tree.noteInB.id), .collection(tree.c.id),
        ]
        let result = BoardWorkspaceState(path: path).canonicalized(for: tree.board)
        #expect(result.state.path == Array(path.prefix(3)))
        #expect(result.issues == [.invalidPath(index: 3), .pathTruncated(index: 3)])

        let twoPages = BoardWorkspaceState(path: [.item(tree.loose.id), .item(tree.noteInB.id)]).canonicalized(for: tree.board)
        #expect(twoPages.state.path == [.item(tree.loose.id)])
    }

    @Test("O filtro vale na lista do mural ou de qualquer pasta, inclusive Pastas, e não na página de um cartão")
    func filterRules() {
        let board = tree.board
        let inFolder: [WorkspaceDestination] = [.collection(tree.a.id), .collection(tree.b.id)]
        for filter in WorkspaceFilter.allCases {
            let atBoard = BoardWorkspaceState(filter: filter).canonicalized(for: board)
            #expect(atBoard.state.filter == filter)
            #expect(atBoard.issues.isEmpty)

            let inside = BoardWorkspaceState(path: inFolder, filter: filter).canonicalized(for: board)
            #expect(inside.state.filter == filter, "\(filter) dentro de uma pasta aninhada")
            #expect(inside.issues.isEmpty)

            let onPage = BoardWorkspaceState(path: inFolder + [.item(tree.noteInB.id)], filter: filter).canonicalized(for: board)
            #expect(onPage.state.filter == nil, "\(filter) na página de um cartão")
            #expect(onPage.issues == [.invalidFilter])
        }
    }

    @Test("Posição de leitura vale para pasta de qualquer nível e aceita pasta como primeiro cartão visível")
    func nestedReadingPositions() {
        let board = tree.board
        let positions: [UUID: ReadingPosition] = [
            tree.a.id: .collection(folderID: tree.a.id, firstVisibleItemID: tree.b.id, relativeOffset: 2, fallbackContentY: 10),
            tree.b.id: .collection(folderID: tree.b.id, firstVisibleItemID: tree.c.id, relativeOffset: 4, fallbackContentY: 120),
            tree.c.id: .collection(folderID: tree.c.id, firstVisibleItemID: tree.noteInC.id, relativeOffset: 0, fallbackContentY: 0),
        ]
        let kept = BoardWorkspaceState(readingPositions: positions).canonicalized(for: board)
        #expect(kept.state.readingPositions == positions)
        #expect(kept.issues.isEmpty)

        let broken = BoardWorkspaceState(readingPositions: [
            // O primeiro cartão visível é de C, não de A.
            tree.a.id: .collection(folderID: tree.a.id, firstVisibleItemID: tree.noteInC.id, relativeOffset: 0, fallbackContentY: 0),
            // Uma nota não é pasta.
            tree.noteInB.id: .collection(folderID: tree.noteInB.id, firstVisibleItemID: nil, relativeOffset: 0, fallbackContentY: 0),
        ]).canonicalized(for: board)
        #expect(broken.state.readingPositions.isEmpty)
        #expect(broken.issues.count == 2)
        #expect(broken.issues.contains(.removedReadingPosition(tree.a.id)))
        #expect(broken.issues.contains(.removedReadingPosition(tree.noteInB.id)))
    }

    @Test("Mural com pastas aninhadas e caminho no terceiro nível sobrevive a gravar e reabrir")
    func repositoryRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MuralNested-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = BoardRepository(rootDirectory: root)
        let id = BoardID()
        let workspace = BoardWorkspaceState(
            contentRevision: 1,
            path: [.collection(tree.a.id), .collection(tree.b.id), .collection(tree.c.id), .item(tree.noteInC.id)])
        try await repository.save(id: id, board: tree.board, workspace: workspace, manifest: BoardManifest(id: id, contentRevision: 1))

        let loaded = try #require(await repository.load(id)).snapshot
        #expect(loaded.board == tree.board)
        #expect(loaded.board.formatVersion == 2)
        #expect(loaded.workspace.path == workspace.path)
    }
}

// MARK: Pacote portátil

@Suite("Pasta dentro de pasta em pacotes portáteis")
struct NestedFolderPackageTests {
    private let tree = NestedTree()

    private func emptyItemsDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MuralNestedPackage-\(UUID().uuidString)", isDirectory: true)
        let items = root.appendingPathComponent("Items", isDirectory: true)
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        return items
    }

    private func expectInvalidParent(
        of expected: BoardItem, in board: Board, using service: BoardPortablePackageService, items: URL,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        await #expect(throws: BoardPortablePackageError.invalidItemParent(expected.id), sourceLocation: sourceLocation) {
            try await service.validateBoard(board, itemsURL: items)
        }
    }

    @Test("O pacote aceita pastas aninhadas até o último nível, com cartões em qualquer uma")
    func acceptsNestedFolders() async throws {
        let items = try emptyItemsDirectory()
        defer { try? FileManager.default.removeItem(at: items.deletingLastPathComponent()) }
        let service = BoardPortablePackageService(availableCapacity: { _ in nil })
        try await service.validateBoard(tree.board, itemsURL: items)

        let chain = folderChain(Board.maximumFolderDepth)
        let inLast = note("No último nível", in: chain.last, at: 30)
        try await service.validateBoard(Board(items: chain + [inLast]), itemsURL: items)
        // A ordem da lista não importa: o filho pode vir antes do pai.
        try await service.validateBoard(Board(items: [inLast] + chain.reversed()), itemsURL: items)
    }

    @Test("O pacote recusa ciclo, profundidade demais e pai que não é pasta")
    func refusesBrokenHierarchies() async throws {
        let items = try emptyItemsDirectory()
        defer { try? FileManager.default.removeItem(at: items.deletingLastPathComponent()) }
        let service = BoardPortablePackageService(availableCapacity: { _ in nil })

        // Ciclo: nenhuma das duas pastas chega ao mural.
        let firstID = UUID()
        let secondID = UUID()
        let first = BoardItem(id: firstID, kind: .folder, title: "A", parentID: secondID)
        let second = BoardItem(id: secondID, kind: .folder, title: "B", parentID: firstID)
        await expectInvalidParent(of: first, in: Board(items: [first, second]), using: service, items: items)
        var selfParent = folder("Própria mãe")
        selfParent.parentID = selfParent.id
        await expectInvalidParent(of: selfParent, in: Board(items: [selfParent]), using: service, items: items)
        let hanging = note("Preso no ciclo", in: first)
        await expectInvalidParent(of: hanging, in: Board(items: [hanging, first, second]), using: service, items: items)

        // Nível 9: a pasta passa do limite.
        let tooDeep = folderChain(Board.maximumFolderDepth + 1)
        await expectInvalidParent(of: tooDeep[Board.maximumFolderDepth], in: Board(items: tooDeep), using: service, items: items)

        // O pai de um cartão tem de ser uma pasta que exista.
        let parentCard = note("Cartão")
        let underCard = note("Sob um cartão", in: parentCard)
        await expectInvalidParent(of: underCard, in: Board(items: [parentCard, underCard]), using: service, items: items)
        let orphan = BoardItem(kind: .text, title: "Órfão", parentID: UUID())
        await expectInvalidParent(of: orphan, in: Board(items: [orphan]), using: service, items: items)
    }
}
