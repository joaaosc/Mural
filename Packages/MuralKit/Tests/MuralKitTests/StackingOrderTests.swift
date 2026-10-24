import Foundation
import Testing

@testable import MuralKit

/// Ids fixos e legíveis: `id(3)` é sempre o mesmo, e a ordem do `uuidString` segue a do número.
private func id(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012ld", number))!
}

/// Gerador com semente fixa (SplitMix64), para os movimentos "aleatórios" serem sempre os mesmos.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

@Suite("Ordem de empilhamento")
struct StackingOrderTests {
    private let a = id(1)
    private let b = id(2)
    private let c = id(3)
    private let d = id(4)
    private let e = id(5)
    private let f = id(6)
    private let g = id(7)

    /// Os números 0, 1, 2… na ordem dada, como a primeira gravação os deixaria.
    private func stacked(_ order: [UUID]) -> [UUID: Double] {
        Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, Double($0)) })
    }

    // MARK: assignments

    @Test("Nada mudou: nenhum número novo")
    func unchangedOrderNeedsNothing() {
        let order = [a, b, c, d]
        #expect(StackingOrder.assignments(for: order, previous: stacked(order)).isEmpty)
        #expect(StackingOrder.assignments(for: [], previous: [:]).isEmpty)
        // Números fracionários, negativos e com buracos também servem.
        #expect(StackingOrder.assignments(for: order, previous: [a: -3.5, b: 0.25, c: 10, d: 11]).isEmpty)
    }

    @Test("Sem números anteriores, todos recebem 0, 1, 2… na ordem")
    func firstNumberingCoversEveryCard() {
        #expect(StackingOrder.assignments(for: [c, a, b], previous: [:]) == [c: 0, a: 1, b: 2])
    }

    @Test("Cartão levado ao topo: só ele muda, para o maior número mais 1")
    func cardMovedToTheTop() {
        let changes = StackingOrder.assignments(for: [a, c, d, b], previous: stacked([a, b, c, d]))
        #expect(changes == [b: 4])
    }

    @Test("Quando levar o segundo de cima ao topo empata com outra escolha, só o cartão levado ao topo muda")
    func topCardTieKeepsTheLowerCards() {
        #expect(StackingOrder.assignments(for: [a, c, b], previous: stacked([a, b, c])) == [b: 3])
        #expect(StackingOrder.assignments(for: [b, a], previous: stacked([a, b])) == [a: 2])
    }

    @Test("Cartão novo no fim ganha o maior número mais 1, e vários seguem de 1 em 1")
    func newCardsAtTheEnd() {
        #expect(StackingOrder.assignments(for: [a, b, c, d], previous: [a: 0.5, b: 7, c: 7.25]) == [d: 8.25])
        #expect(StackingOrder.assignments(for: [a, b, c, d, e], previous: stacked([a, b, c])) == [d: 3, e: 4])
    }

    @Test("Cartão novo no começo ganha o menor número menos 1, e no meio fica entre os vizinhos")
    func newCardsAtTheStartAndInTheMiddle() {
        #expect(StackingOrder.assignments(for: [d, a, b], previous: [a: 0, b: 1]) == [d: -1])
        #expect(StackingOrder.assignments(for: [e, d, a, b], previous: [a: 0, b: 1]) == [e: -2, d: -1])
        #expect(StackingOrder.assignments(for: [a, d, b], previous: [a: 0, b: 1]) == [d: 0.5])
    }

    @Test("Cartão movido para o meio fica estritamente entre os vizinhos")
    func cardMovedToTheMiddle() throws {
        let changes = StackingOrder.assignments(for: [a, d, b, c], previous: stacked([a, b, c, d]))
        #expect(Set(changes.keys) == [d])
        let layer = try #require(changes[d])
        #expect(layer > 0 && layer < 1)
    }

    @Test("Cartão movido para baixo fica abaixo do menor número")
    func cardMovedToTheBottom() throws {
        let changes = StackingOrder.assignments(for: [d, a, b, c], previous: stacked([a, b, c, d]))
        #expect(Set(changes.keys) == [d])
        #expect(try #require(changes[d]) < 0)
        #expect(changes == [d: -1])
    }

    @Test("Vários cartões movidos de uma vez: só os que saíram do lugar mudam")
    func severalCardsMoved() {
        // a vai para o topo e g para o fundo; b, c, d, e e f seguem em ordem.
        let changes = StackingOrder.assignments(for: [g, b, c, d, e, f, a], previous: stacked([a, b, c, d, e, f, g]))
        #expect(changes == [g: 0, a: 6])
    }

    @Test("Vários cartões no mesmo vão ficam igualmente espaçados entre os vizinhos")
    func severalCardsInTheSameGap() throws {
        let changes = StackingOrder.assignments(for: [a, e, f, b, c, d], previous: stacked([a, b, c, d, e, f]))
        #expect(Set(changes.keys) == [e, f])
        let first = try #require(changes[e])
        let second = try #require(changes[f])
        #expect(0 < first && first < second && second < 1)
        #expect(abs(first - (second - first)) < 1e-12)
        #expect(abs((second - first) - (1 - second)) < 1e-12)
    }

    @Test("Sem precisão para um número entre os vizinhos, todos são renumerados na ordem")
    func exhaustedPrecisionBetweenNeighboursRenumbersEverything() {
        // Entre 1.0 e o Double seguinte não cabe nenhum número.
        let previous = [a: 1.0, b: 1.0.nextUp]
        let order = [a, c, b]
        let changes = StackingOrder.assignments(for: order, previous: previous)
        #expect(changes == [a: 0, c: 1, b: 2])
        #expect(StackingOrder.sorted(order, layers: previous.merging(changes) { $1 }) == order)
    }

    @Test("Sem precisão para somar 1, subtrair 1 ou medir o vão, todos são renumerados")
    func exhaustedPrecisionAtTheEdgesRenumbersEverything() {
        // Em 1e18 o passo entre dois Double é 128: somar ou subtrair 1 não muda o número.
        #expect(StackingOrder.assignments(for: [a, b, c], previous: [a: 1e18, b: 2e18]) == [a: 0, b: 1, c: 2])
        #expect(StackingOrder.assignments(for: [c, a, b], previous: [a: -1e18, b: 0]) == [c: 0, a: 1, b: 2])
        #expect(
            StackingOrder.assignments(for: [a, b], previous: [a: Double.greatestFiniteMagnitude]) == [a: 0, b: 1])
        // O vão entre os extremos nem cabe num Double.
        let extremes = [a: -Double.greatestFiniteMagnitude, b: Double.greatestFiniteMagnitude]
        #expect(StackingOrder.assignments(for: [a, c, b], previous: extremes) == [a: 0, c: 1, b: 2])
    }

    @Test("Números de cartões que não estão na ordem são ignorados")
    func idsOutsideTheOrderAreIgnored() {
        let previous = stacked([a, b, c]).merging([f: 100, g: -100]) { $1 }
        #expect(StackingOrder.assignments(for: [a, b, c, d], previous: previous) == [d: 3])
        #expect(StackingOrder.assignments(for: [b], previous: previous).isEmpty)
    }

    @Test("Número anterior que não é finito conta como ausente")
    func nonFiniteLayersCountAsMissing() {
        #expect(StackingOrder.assignments(for: [a, b, c], previous: [a: 0, b: .nan, c: .infinity]) == [b: 1, c: 2])
        #expect(StackingOrder.assignments(for: [a, b], previous: [a: .infinity, b: 0]) == [a: -1])
        #expect(StackingOrder.assignments(for: [a, b], previous: [a: .nan, b: 0]) == [a: -1])
    }

    @Test("Um id repetido na ordem vale só na primeira vez")
    func repeatedIDsCountOnce() {
        #expect(StackingOrder.assignments(for: [a, b, a], previous: [a: 0]) == [b: 1])
    }

    @Test("Dois cartões com o mesmo número anterior não ficam os dois: o de baixo mantém, o outro ganha número novo")
    func equalPreviousLayersKeepOnlyOne() {
        #expect(StackingOrder.assignments(for: [a, b], previous: [a: 1, b: 1]) == [b: 2])
        #expect(StackingOrder.assignments(for: [a, b, c], previous: [a: 1, b: 1, c: 2]) == [b: 1.5])
    }

    // MARK: sorted

    @Test("A ordem pelos números desempata pelo uuidString")
    func sortedBreaksTiesByID() {
        // a e c empatam em 1; vale o menor uuidString.
        #expect(StackingOrder.sorted([c, b, a], layers: [a: 1, b: 0, c: 1]) == [b, a, c])
    }

    @Test("Cartões sem número vão para o fim, na ordem em que vieram")
    func sortedPutsUnnumberedCardsLast() {
        #expect(StackingOrder.sorted([e, b, d, a, c], layers: [a: 2, b: 1]) == [b, a, e, d, c])
        #expect(StackingOrder.sorted([c, a, b], layers: [a: .nan, b: 5]) == [b, c, a])
        #expect(StackingOrder.sorted([], layers: [a: 1]).isEmpty)
    }

    // MARK: Propriedade

    @Test("Em movimentos fixos e pseudoaleatórios, ordenar pelos números reproduz a ordem a cada passo")
    func randomMovesKeepTheOrder() {
        var generator = SeededGenerator(seed: 2026)
        var nextNumber = 100
        var order = (0..<10).map { _ in
            nextNumber += 1
            return id(nextNumber)
        }
        var layers = StackingOrder.assignments(for: order, previous: [:])
        #expect(StackingOrder.sorted(order, layers: layers) == order)

        func move(_ count: Int) {
            for _ in 0..<count {
                let card = order.remove(at: Int.random(in: 0..<order.count, using: &generator))
                order.insert(card, at: Int.random(in: 0...order.count, using: &generator))
            }
        }

        for step in 1...400 {
            var singleChange = true
            switch Int.random(in: 0..<5, using: &generator) {
            case 0:
                move(1)
            case 1:
                order.append(order.remove(at: Int.random(in: 0..<order.count, using: &generator)))
            case 2:
                nextNumber += 1
                order.insert(id(nextNumber), at: Int.random(in: 0...order.count, using: &generator))
            case 3 where order.count > 3:
                order.remove(at: Int.random(in: 0..<order.count, using: &generator))
                singleChange = false
            default:
                move(Int.random(in: 2...3, using: &generator))
                singleChange = false
            }

            let changes = StackingOrder.assignments(for: order, previous: layers)
            #expect(changes.keys.allSatisfy(order.contains), "passo \(step): número para um cartão fora da ordem")
            if singleChange {
                // Um cartão movido ou novo muda sozinho, a menos que a precisão tenha esgotado.
                #expect(changes.count <= 1 || changes.count == order.count, "passo \(step): \(changes.count) números")
            }
            layers.merge(changes) { $1 }
            #expect(StackingOrder.sorted(order, layers: layers) == order, "passo \(step)")
        }
    }
}

@Suite("Ordem de criação dos filhos")
struct ChildrenCreationOrderTests {
    private let instant = Date(timeIntervalSince1970: 1_000)
    private let folder = BoardItem(id: id(100), kind: .folder, title: "Pasta", createdAt: Date(timeIntervalSince1970: 0))

    private func child(_ number: Int, createdAt: Date) -> BoardItem {
        BoardItem(id: id(number), kind: .text, title: "Cartão \(number)", createdAt: createdAt, parentID: folder.id)
    }

    @Test("Filhos criados no mesmo instante saem pelo id, seja qual for a ordem da lista")
    func equalDatesBreakTiesByID() {
        let first = child(1, createdAt: instant)
        let second = child(2, createdAt: instant)
        for items in [[folder, first, second], [folder, second, first]] {
            let board = Board(items: items)
            #expect(board.children(of: folder.id).map(\.id) == [first.id, second.id])
            #expect(board.descendants(of: folder.id).map(\.id) == [first.id, second.id])
        }
    }

    @Test("A data vem antes do id: o mais antigo sai primeiro mesmo com o id maior")
    func dateComesBeforeID() {
        let older = child(2, createdAt: instant)
        let newer = child(1, createdAt: instant.addingTimeInterval(1))
        let board = Board(items: [folder, newer, older])
        #expect(board.children(of: folder.id).map(\.id) == [older.id, newer.id])
        #expect(board.descendants(of: folder.id).map(\.id) == [older.id, newer.id])
    }
}
