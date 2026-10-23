import Foundation
import Testing

@testable import MuralKit

@Suite("Vitrine de murais do painel")
struct BoardPickerTests {
    private func date(_ seconds: Double) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func entry(_ name: String, updatedAt: Double = 0, id: BoardID = BoardID(), route: BoardRoute? = nil) -> BoardLibraryEntry {
        BoardLibraryEntry(
            manifest: BoardManifest(id: id, name: name, createdAt: date(0), updatedAt: date(updatedAt)),
            route: route ?? .saved(id))
    }

    private func entries(named names: [String]) -> [BoardLibraryEntry] {
        names.map { entry($0) }
    }

    // MARK: Mural do centro ao abrir

    @Test("Lista vazia não tem mural inicial, mesmo com ids pedidos")
    func initialIndexOfEmptyList() {
        #expect(BoardPicker.initialIndex(in: [], lastDestination: nil, activeBoard: nil) == nil)
        #expect(BoardPicker.initialIndex(in: [], lastDestination: BoardID(), activeBoard: BoardID()) == nil)
    }

    @Test("O último mural usado pelo painel vence a aba ativa e a data")
    func lastDestinationWinsFirst() {
        let list = [entry("A", updatedAt: 300), entry("B", updatedAt: 200), entry("C", updatedAt: 100)]

        let index = BoardPicker.initialIndex(in: list, lastDestination: list[2].manifest.id, activeBoard: list[1].manifest.id)

        #expect(index == 2)
    }

    @Test("Sem último destino, vale o mural da aba ativa, mesmo que não seja o mais recente")
    func activeBoardIsSecond() {
        let list = [entry("A", updatedAt: 300), entry("B", updatedAt: 200), entry("C", updatedAt: 100)]

        #expect(BoardPicker.initialIndex(in: list, lastDestination: nil, activeBoard: list[2].manifest.id) == 2)
    }

    @Test("Sem último destino nem aba ativa, vale o de atualização mais recente")
    func newestUpdateIsLast() {
        let list = [entry("A", updatedAt: 100), entry("B", updatedAt: 300), entry("C", updatedAt: 200)]

        #expect(BoardPicker.initialIndex(in: list, lastDestination: nil, activeBoard: nil) == 1)
    }

    @Test("O último destino fora da lista cai para a aba ativa; os dois fora da lista caem para o mais recente")
    func unknownIDsFallThrough() {
        let list = [entry("A", updatedAt: 100), entry("B", updatedAt: 300), entry("C", updatedAt: 200)]

        #expect(BoardPicker.initialIndex(in: list, lastDestination: BoardID(), activeBoard: list[2].manifest.id) == 2)
        #expect(BoardPicker.initialIndex(in: list, lastDestination: BoardID(), activeBoard: BoardID()) == 1)
        #expect(BoardPicker.initialIndex(in: list, lastDestination: BoardID(), activeBoard: nil) == 1)
        #expect(BoardPicker.initialIndex(in: list, lastDestination: nil, activeBoard: BoardID()) == 1)
    }

    @Test("Em empate de data, vale o primeiro da lista")
    func tieGoesToTheFirst() {
        let list = [entry("A", updatedAt: 100), entry("B", updatedAt: 300), entry("C", updatedAt: 300), entry("D", updatedAt: 300)]
        #expect(BoardPicker.initialIndex(in: list, lastDestination: nil, activeBoard: nil) == 1)

        let allEqual = entries(named: ["A", "B", "C"])
        #expect(BoardPicker.initialIndex(in: allEqual, lastDestination: nil, activeBoard: nil) == 0)
    }

    @Test("A data mais recente não depende da posição: pode ser a última da lista")
    func newestCanBeTheLast() {
        let list = [entry("A", updatedAt: 100), entry("B", updatedAt: 200), entry("C", updatedAt: 900)]

        #expect(BoardPicker.initialIndex(in: list, lastDestination: nil, activeBoard: nil) == 2)
    }

    @Test("Um mural só é sempre o inicial")
    func singleEntry() {
        let list = entries(named: ["Único"])

        #expect(BoardPicker.initialIndex(in: list, lastDestination: nil, activeBoard: nil) == 0)
        #expect(BoardPicker.initialIndex(in: list, lastDestination: BoardID(), activeBoard: BoardID()) == 0)
    }

    @Test("O id de uma entrada é o do manifesto, também para o rascunho de exemplo")
    func idComesFromTheManifest() {
        let draftID = BoardID()
        let list = [entry("A", updatedAt: 500), entry("Exemplo", updatedAt: 1, id: draftID, route: .welcomeDraft(draftID))]

        #expect(BoardPicker.initialIndex(in: list, lastDestination: draftID, activeBoard: nil) == 1)
    }

    // MARK: Busca por nome

    @Test("Acha primeiro o nome que começa com o texto, a partir do começo da lista")
    func prefixMatchFromTheStart() {
        let list = entries(named: ["Casa", "Escola", "Escritório", "Obra"])

        #expect(BoardPicker.index(matching: "es", in: list) == 1)
        #expect(BoardPicker.index(matching: "escr", in: list) == 2)
        #expect(BoardPicker.index(matching: "obra", in: list) == 3)
    }

    @Test("Um nome que começa com o texto vale mais que um que só o contém, mesmo mais adiante na lista")
    func prefixBeatsContains() {
        let list = entries(named: ["Minha casa", "Casa velha", "Obra"])

        #expect(BoardPicker.index(matching: "cas", in: list) == 1)
        #expect(BoardPicker.index(matching: "cas", in: list, startingAt: 2) == 1, "dá a volta e acha o que começa com o texto")
    }

    @Test("Sem nenhum nome que comece com o texto, vale o primeiro que o contém")
    func containsWhenNothingStartsWith() {
        let list = entries(named: ["Casa", "Minha escola", "Sua escola", "Obra"])

        #expect(BoardPicker.index(matching: "esc", in: list) == 1)
        #expect(BoardPicker.index(matching: "esc", in: list, startingAt: 2) == 2)
        #expect(BoardPicker.index(matching: "esc", in: list, startingAt: 3) == 1, "dá a volta")
        #expect(BoardPicker.index(matching: "bra", in: list) == 3)
    }

    @Test("Não diferencia maiúsculas nem acentos, nos dois sentidos")
    func ignoresCaseAndDiacritics() {
        let list = entries(named: ["Cabana", "Café", "Ação", "Resumo"])

        #expect(BoardPicker.index(matching: "cafe", in: list) == 1)
        #expect(BoardPicker.index(matching: "CAFÉ", in: list) == 1)
        #expect(BoardPicker.index(matching: "caf", in: list) == 1)
        #expect(BoardPicker.index(matching: "acao", in: list) == 2)
        #expect(BoardPicker.index(matching: "AÇÃO", in: list) == 2)
        #expect(BoardPicker.index(matching: "RESUMO", in: entries(named: ["resumo"])) == 0)
        #expect(BoardPicker.index(matching: "cafe", in: entries(named: ["Cafe"])) == 0, "sem acento no nome")
        #expect(BoardPicker.index(matching: "mo", in: list) == 3, "contém, sem diferença de caixa")
        #expect(BoardPicker.index(matching: "cao", in: list) == 2, "contém, sem diferença de acento")
    }

    @Test("A busca começa em start (inclusive) e dá a volta no fim da lista")
    func wrapsAroundTheList() {
        let list = entries(named: ["Alfa", "Beta", "Alfeu", "Gama", "Alvo"])

        #expect(BoardPicker.index(matching: "al", in: list) == 0)
        #expect(BoardPicker.index(matching: "al", in: list, startingAt: 0) == 0, "start é inclusive")
        #expect(BoardPicker.index(matching: "al", in: list, startingAt: 1) == 2)
        #expect(BoardPicker.index(matching: "al", in: list, startingAt: 2) == 2, "start é inclusive")
        #expect(BoardPicker.index(matching: "al", in: list, startingAt: 3) == 4)
        #expect(BoardPicker.index(matching: "al", in: list, startingAt: 4) == 4)
        #expect(BoardPicker.index(matching: "alf", in: list, startingAt: 3) == 0, "passa do fim e volta ao início")
        #expect(BoardPicker.index(matching: "alfa", in: list, startingAt: 1) == 0, "só há um, e é o primeiro")
    }

    @Test("Um start fora da lista também dá a volta")
    func startOutsideTheListWraps() {
        let list = entries(named: ["Alfa", "Beta", "Alfeu"])

        #expect(BoardPicker.index(matching: "al", in: list, startingAt: 3) == 0, "o tamanho da lista vale como 0")
        #expect(BoardPicker.index(matching: "al", in: list, startingAt: 4) == 2, "4 vale como 1")
        #expect(BoardPicker.index(matching: "al", in: list, startingAt: 100) == 2, "100 vale como 1")
        #expect(BoardPicker.index(matching: "al", in: list, startingAt: -1) == 2, "-1 é o último")
        #expect(BoardPicker.index(matching: "al", in: list, startingAt: -3) == 0)
    }

    @Test("Texto vazio, só espaços ou só quebras de linha não procura nada")
    func blankQueryFindsNothing() {
        let list = entries(named: ["Casa", " ", ""])

        for query in ["", " ", "   ", "\n", "\t \n"] {
            #expect(BoardPicker.index(matching: query, in: list) == nil, "\(query.debugDescription)")
        }
    }

    @Test("Os espaços nas pontas do texto são ignorados, e os do meio contam")
    func trimsTheQuery() {
        let list = entries(named: ["Casa", "Casa nova", "Obra"])

        #expect(BoardPicker.index(matching: "  casa  ", in: list) == 0)
        #expect(BoardPicker.index(matching: "casa nova\n", in: list) == 1)
        #expect(BoardPicker.index(matching: "casa  nova", in: list) == nil, "dois espaços no meio não são o espaço do nome")
    }

    @Test("Sem nome que sirva, ou com a lista vazia, devolve nil")
    func noMatch() {
        let list = entries(named: ["Casa", "Escola"])

        #expect(BoardPicker.index(matching: "xyz", in: list) == nil)
        #expect(BoardPicker.index(matching: "casas", in: list) == nil, "o texto é maior que o nome")
        #expect(BoardPicker.index(matching: "casa", in: []) == nil)
        #expect(BoardPicker.index(matching: "casa", in: [], startingAt: 5) == nil)
    }

    @Test("A busca usa a ordem da lista recebida, sem reordená-la")
    func keepsTheReceivedOrder() {
        let zeta = entry("Zeta", updatedAt: 1)
        let alfa = entry("Alfa", updatedAt: 2)
        let list = [zeta, alfa]

        #expect(BoardPicker.index(matching: "a", in: list) == 1, "Alfa começa com a; Zeta só contém")
        #expect(BoardPicker.index(matching: "z", in: list) == 0)
        #expect(BoardPicker.initialIndex(in: list, lastDestination: nil, activeBoard: nil) == 1)
    }
}
