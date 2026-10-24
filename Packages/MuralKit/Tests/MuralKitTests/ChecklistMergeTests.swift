import Foundation
import Testing

@testable import MuralKit

// MARK: Fixtures

/// Ids fixos e legíveis: `id(3)` é sempre o mesmo.
private func id(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012ld", number))!
}

private func entry(_ number: Int, _ text: String, done: Bool = false) -> ChecklistEntry {
    ChecklistEntry(id: id(number), text: text, isDone: done)
}

private func section(_ number: Int, _ title: String, _ entries: [ChecklistEntry] = []) -> ChecklistSection {
    ChecklistSection(id: id(number), title: title, entries: entries)
}

private func list(_ sections: [ChecklistSection], title: String = "Compras", intro: String = "") -> ChecklistDocument {
    ChecklistDocument(title: title, intro: intro, sections: sections)
}

/// A lista de compras do exemplo: uma seção com leite (11), pão (12) e ovos (13), cada um marcado ou não.
private func shopping(milk: Bool = false, bread: Bool = false, eggs: Bool = false) -> ChecklistDocument {
    list([section(1, "Mercado", [entry(11, "leite", done: milk), entry(12, "pão", done: bread), entry(13, "ovos", done: eggs)])])
}

/// Cada seção numa linha, com os itens na ordem e o `✓` nos marcados: dá para ler a ordem do resultado de uma vez.
private func outline(_ document: ChecklistDocument) -> [String] {
    document.sections.map { section in
        section.title + ":" + section.entries.map { " " + ($0.isDone ? "✓ " : "") + $0.text }.joined(separator: ",")
    }
}

/// Os ids de todos os itens, na ordem da lista, para conferir que nenhum aparece duas vezes.
private func entryIDs(_ document: ChecklistDocument) -> [UUID] {
    document.sections.flatMap(\.entries).map(\.id)
}

/// Gerador com semente fixa (SplitMix64), para os sorteios serem sempre os mesmos.
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

/// Uma lista com três seções de zero a quatro itens cada uma.
private func randomList(using generator: inout SeededGenerator) -> ChecklistDocument {
    var next = 10
    var sections: [ChecklistSection] = []
    for number in 1...3 {
        let entries = (0..<Int.random(in: 0...4, using: &generator)).map { _ -> ChecklistEntry in
            next += 1
            return entry(next, "item \(next)")
        }
        sections.append(section(number, "Seção \(number)", entries))
    }
    return list(sections)
}

/// A lista depois de edições sorteadas de um lado: marcar, reescrever, apagar e reordenar itens, levar um item para outra seção,
/// acrescentar itens e seções, reordenar as seções. `idBase` separa os ids novos de cada lado. Com `appendOnly`, o que entra ou é
/// levado para uma seção vai sempre para o fim dela, e a seção nova vai para o fim da lista.
private func edited(
    _ document: ChecklistDocument, idBase: Int, appendOnly: Bool, using generator: inout SeededGenerator
) -> ChecklistDocument {
    var result = document
    var next = idBase
    func chance(_ outOf: Int) -> Bool { Int.random(in: 0..<outOf, using: &generator) == 0 }
    func newEntry() -> ChecklistEntry {
        next += 1
        return entry(next, "novo \(next)")
    }
    func position(in count: Int) -> Int { appendOnly ? count : Int.random(in: 0...count, using: &generator) }

    for index in result.sections.indices {
        for entryIndex in result.sections[index].entries.indices.reversed() {
            if chance(8) {
                result.sections[index].entries.remove(at: entryIndex)
                continue
            }
            if chance(4) { result.sections[index].entries[entryIndex].isDone.toggle() }
            if chance(6) { result.sections[index].entries[entryIndex].text = "reescrito \(idBase) \(entryIndex)" }
        }
        if chance(3) { result.sections[index].entries.shuffle(using: &generator) }
    }
    if chance(4), let from = result.sections.indices.randomElement(using: &generator),
        let moved = result.sections[from].entries.indices.randomElement(using: &generator)
    {
        let item = result.sections[from].entries.remove(at: moved)
        let to = result.sections.indices.randomElement(using: &generator) ?? from
        result.sections[to].entries.insert(item, at: position(in: result.sections[to].entries.count))
    }
    if chance(3), let target = result.sections.indices.randomElement(using: &generator) {
        result.sections[target].entries.insert(newEntry(), at: position(in: result.sections[target].entries.count))
    }
    if chance(4) { result.sections.shuffle(using: &generator) }
    if chance(4) {
        result.sections.insert(section(idBase + 90, "Seção nova", [newEntry()]), at: position(in: result.sections.count))
    }
    if chance(5) { result.title = "Título \(idBase)" }
    return result
}

// MARK: Testes

@Suite("Junção de lista por item")
struct ChecklistMergeTests {
    // MARK: Lista de compras

    @Test("Lista de compras: uma pessoa marca o leite e a outra o pão, e as duas marcações ficam")
    func shoppingListKeepsBothMarks() throws {
        let merged = try #require(ChecklistMerge.merge(base: shopping(), local: shopping(milk: true), remote: shopping(bread: true)))
        #expect(outline(merged) == ["Mercado: ✓ leite, ✓ pão, ovos"])
        // Trocar os lados dá a mesma lista.
        #expect(ChecklistMerge.merge(base: shopping(), local: shopping(bread: true), remote: shopping(milk: true)) == merged)
    }

    @Test("Sem diferença entre os lados, a lista volta igual")
    func identicalListsStayTheSame() {
        let all = list(
            [section(1, "Mercado", [entry(11, "leite", done: true)]), section(2, "Casa", [entry(21, "lâmpada")])], intro: "Sábado")
        #expect(ChecklistMerge.merge(base: all, local: all, remote: all) == all)
    }

    // MARK: Campos de um item

    @Test("Marcação: vale o lado que mudou, marcando ou desmarcando")
    func markFollowsWhoChangedIt() throws {
        let marked = try #require(ChecklistMerge.merge(base: shopping(), local: shopping(milk: true), remote: shopping()))
        #expect(outline(marked) == ["Mercado: ✓ leite, pão, ovos"])

        // O local desmarca o leite e o remote marca o pão.
        let unmarked = try #require(
            ChecklistMerge.merge(base: shopping(milk: true), local: shopping(), remote: shopping(milk: true, bread: true)))
        #expect(outline(unmarked) == ["Mercado: leite, ✓ pão, ovos"])

        // O remote marca e o local não mexe.
        let remoteMarked = try #require(ChecklistMerge.merge(base: shopping(), local: shopping(), remote: shopping(eggs: true)))
        #expect(outline(remoteMarked) == ["Mercado: leite, pão, ✓ ovos"])
    }

    @Test("O mesmo item marcado num lado e desmarcado no outro fica como no local")
    func markedAndUnmarkedKeepsLocal() throws {
        // Sem o item na base não há quem tenha mudado: o mesmo item nasceu nos dois lados, marcado num e desmarcado no outro.
        let base = list([section(1, "Mercado")])
        let marked = list([section(1, "Mercado", [entry(11, "leite", done: true)])])
        let unmarked = list([section(1, "Mercado", [entry(11, "leite", done: false)])])
        #expect(outline(try #require(ChecklistMerge.merge(base: base, local: marked, remote: unmarked))) == ["Mercado: ✓ leite"])
        #expect(outline(try #require(ChecklistMerge.merge(base: base, local: unmarked, remote: marked))) == ["Mercado: leite"])
    }

    @Test("Campos diferentes do mesmo item: o texto de um lado e a marcação do outro entram")
    func differentFieldsOfTheSameEntry() throws {
        let base = list([section(1, "Mercado", [entry(11, "leite")])])
        let local = list([section(1, "Mercado", [entry(11, "leite desnatado")])])
        let remote = list([section(1, "Mercado", [entry(11, "leite", done: true)])])
        let merged = try #require(ChecklistMerge.merge(base: base, local: local, remote: remote))
        #expect(outline(merged) == ["Mercado: ✓ leite desnatado"])
    }

    @Test("Texto do mesmo item editado dos dois jeitos é conflito; editado igual nos dois, entra")
    func sameEntryTextEditedDifferently() throws {
        let base = list([section(1, "Mercado", [entry(11, "leite"), entry(12, "pão")])])
        let local = list([section(1, "Mercado", [entry(11, "leite integral"), entry(12, "pão")])])
        let remote = list([section(1, "Mercado", [entry(11, "leite desnatado"), entry(12, "pão")])])
        #expect(ChecklistMerge.merge(base: base, local: local, remote: remote) == nil)

        let sameEdit = list([section(1, "Mercado", [entry(11, "leite integral"), entry(12, "pão", done: true)])])
        let merged = try #require(ChecklistMerge.merge(base: base, local: local, remote: sameEdit))
        #expect(outline(merged) == ["Mercado: leite integral, ✓ pão"])
    }

    // MARK: Itens novos e apagados

    @Test("Item novo de cada lado: os dois entram, o do remote no fim da seção onde ele está lá")
    func newEntryOnEachSide() throws {
        let base = list([section(1, "Mercado", [entry(11, "leite")]), section(2, "Farmácia", [entry(21, "xarope")])])
        let local = list([section(1, "Mercado", [entry(11, "leite"), entry(12, "café")]), section(2, "Farmácia", [entry(21, "xarope")])])
        let remote = list([
            section(1, "Mercado", [entry(13, "açúcar"), entry(11, "leite")]),
            section(2, "Farmácia", [entry(21, "xarope"), entry(22, "curativo")]),
        ])
        let merged = try #require(ChecklistMerge.merge(base: base, local: local, remote: remote))
        #expect(outline(merged) == ["Mercado: leite, café, açúcar", "Farmácia: xarope, curativo"])
    }

    @Test("Item apagado de um lado e intocado do outro sai")
    func deletedAndUntouchedLeaves() throws {
        let withoutBread = list([section(1, "Mercado", [entry(11, "leite"), entry(13, "ovos")])])
        let deletedHere = try #require(ChecklistMerge.merge(base: shopping(), local: withoutBread, remote: shopping(milk: true)))
        #expect(outline(deletedHere) == ["Mercado: ✓ leite, ovos"])

        let deletedThere = try #require(ChecklistMerge.merge(base: shopping(), local: shopping(milk: true), remote: withoutBread))
        #expect(outline(deletedThere) == ["Mercado: ✓ leite, ovos"])
    }

    @Test("Item apagado de um lado e alterado no outro é conflito")
    func deletedAndEditedIsConflict() {
        let withoutBread = list([section(1, "Mercado", [entry(11, "leite"), entry(13, "ovos")])])
        let breadMarked = shopping(bread: true)
        let breadRenamed = list([section(1, "Mercado", [entry(11, "leite"), entry(12, "pão francês"), entry(13, "ovos")])])
        for edited in [breadMarked, breadRenamed] {
            #expect(ChecklistMerge.merge(base: shopping(), local: withoutBread, remote: edited) == nil)
            #expect(ChecklistMerge.merge(base: shopping(), local: edited, remote: withoutBread) == nil)
        }
    }

    // MARK: Seções

    @Test("Seção nova no remote vai para o fim da lista, depois das novas do local")
    func newRemoteSectionGoesLast() throws {
        let base = list([section(1, "Mercado", [entry(11, "leite")])])
        let local = list([section(1, "Mercado", [entry(11, "leite")]), section(3, "Casa", [entry(31, "lâmpada")])])
        let remote = list([section(2, "Farmácia", [entry(21, "xarope")]), section(1, "Mercado", [entry(11, "leite")])])
        let merged = try #require(ChecklistMerge.merge(base: base, local: local, remote: remote))
        #expect(outline(merged) == ["Mercado: leite", "Casa: lâmpada", "Farmácia: xarope"])
    }

    @Test("Título de seção: vale o lado que mudou e, mudado dos dois jeitos, o do local")
    func sectionTitle() throws {
        let base = list([section(1, "Mercado")])
        let renamedHere = list([section(1, "Supermercado")])
        let renamedThere = list([section(1, "Feira")])
        #expect(outline(try #require(ChecklistMerge.merge(base: base, local: renamedHere, remote: base))) == ["Supermercado:"])
        #expect(outline(try #require(ChecklistMerge.merge(base: base, local: base, remote: renamedThere))) == ["Feira:"])
        #expect(outline(try #require(ChecklistMerge.merge(base: base, local: renamedHere, remote: renamedThere))) == ["Supermercado:"])
    }

    @Test("Seção apagada de um lado e intocada do outro sai com os itens; apagada e renomeada é conflito")
    func deletedSection() throws {
        let base = list([section(1, "Mercado", [entry(11, "leite")]), section(2, "Casa", [entry(21, "lâmpada")])])
        let withoutHome = list([section(1, "Mercado", [entry(11, "leite")])])
        let milkMarked = list([section(1, "Mercado", [entry(11, "leite", done: true)]), section(2, "Casa", [entry(21, "lâmpada")])])
        let merged = try #require(ChecklistMerge.merge(base: base, local: withoutHome, remote: milkMarked))
        #expect(outline(merged) == ["Mercado: ✓ leite"])

        let homeRenamed = list([section(1, "Mercado", [entry(11, "leite")]), section(2, "Casa nova", [entry(21, "lâmpada")])])
        #expect(ChecklistMerge.merge(base: base, local: withoutHome, remote: homeRenamed) == nil)
        #expect(ChecklistMerge.merge(base: base, local: homeRenamed, remote: withoutHome) == nil)
    }

    @Test("Item novo do remote numa seção que o local apagou vai para a primeira seção que sobrou")
    func newRemoteEntryInDeletedSection() throws {
        let base = list([section(1, "Mercado", [entry(11, "leite")]), section(2, "Casa", [entry(21, "lâmpada")])])
        let local = list([section(1, "Mercado", [entry(11, "leite")])])
        let remote = list([section(1, "Mercado", [entry(11, "leite")]), section(2, "Casa", [entry(21, "lâmpada"), entry(22, "pilha")])])
        let merged = try #require(ChecklistMerge.merge(base: base, local: local, remote: remote))
        #expect(outline(merged) == ["Mercado: leite, pilha"])
    }

    @Test("Sem nenhuma seção sobrando, a seção do item novo vem junto")
    func sectionComesAlongWhenNoneIsLeft() throws {
        let base = list([section(1, "Mercado", [entry(11, "leite")])])
        let remote = list([section(1, "Mercado", [entry(11, "leite"), entry(12, "pão"), entry(13, "ovos")])])
        let merged = try #require(ChecklistMerge.merge(base: base, local: list([]), remote: remote))
        #expect(outline(merged) == ["Mercado: pão, ovos"])
        #expect(merged.sections.map(\.id) == [id(1)])
    }

    // MARK: Item em outra seção

    @Test("Item que mudou de seção fica na seção de quem o moveu e, movido nos dois lados, na do local, sem aparecer duas vezes")
    func movedEntryFollowsWhoMovedIt() throws {
        // O local leva o x de A para B; o remote não o move, mas marca o y.
        let base = list([section(1, "A", [entry(11, "x"), entry(12, "y")]), section(2, "B")])
        let local = list([section(1, "A", [entry(12, "y")]), section(2, "B", [entry(11, "x")])])
        let remote = list([section(1, "A", [entry(11, "x"), entry(12, "y", done: true)]), section(2, "B")])
        let movedHere = try #require(ChecklistMerge.merge(base: base, local: local, remote: remote))
        #expect(outline(movedHere) == ["A: ✓ y", "B: x"])
        #expect(entryIDs(movedHere).count == Set(entryIDs(movedHere)).count)

        // Os dois levam o x para seções diferentes.
        let threeSections = list([section(1, "A", [entry(11, "x")]), section(2, "B"), section(3, "C")])
        let toB = list([section(1, "A"), section(2, "B", [entry(11, "x")]), section(3, "C")])
        let toC = list([section(1, "A"), section(2, "B"), section(3, "C", [entry(11, "x")])])
        let bothMoved = try #require(ChecklistMerge.merge(base: threeSections, local: toB, remote: toC))
        #expect(outline(bothMoved) == ["A:", "B: x", "C:"])

        // Só o remote o move, e o local acrescenta outro item: o x vai para a seção que o remote deu a ele.
        let notMoved = list([section(1, "A", [entry(11, "x")]), section(2, "B")])
        let localAddsOne = list([section(1, "A", [entry(11, "x"), entry(13, "z")]), section(2, "B")])
        let movedThere = list([section(1, "A"), section(2, "B", [entry(11, "x")])])
        let followsRemote = try #require(ChecklistMerge.merge(base: notMoved, local: localAddsOne, remote: movedThere))
        #expect(outline(followsRemote) == ["A: z", "B: x"])
        #expect(entryIDs(followsRemote).count == Set(entryIDs(followsRemote)).count)
    }

    // MARK: Ordem

    @Test("Só o remote reordenou os itens e o local marcou um: vale a ordem do remote, com a marcação")
    func remoteOrderWinsOverALocalMark() throws {
        let base = list([section(1, "A", [entry(11, "x"), entry(12, "y"), entry(13, "z")])])
        let marked = list([section(1, "A", [entry(11, "x"), entry(12, "y", done: true), entry(13, "z")])])
        let reordered = list([section(1, "A", [entry(13, "z"), entry(11, "x"), entry(12, "y")])])
        let merged = try #require(ChecklistMerge.merge(base: base, local: marked, remote: reordered))
        #expect(outline(merged) == ["A: z, x, ✓ y"])
    }

    @Test("Só o local reordenou os itens e o remote marcou um: vale a ordem do local, com a marcação")
    func localOrderWinsOverARemoteMark() throws {
        let base = list([section(1, "A", [entry(11, "x"), entry(12, "y"), entry(13, "z")])])
        let reordered = list([section(1, "A", [entry(13, "z"), entry(11, "x"), entry(12, "y")])])
        let marked = list([section(1, "A", [entry(11, "x"), entry(12, "y", done: true), entry(13, "z")])])
        let merged = try #require(ChecklistMerge.merge(base: base, local: reordered, remote: marked))
        #expect(outline(merged) == ["A: z, x, ✓ y"])
    }

    @Test("Reordenado nos dois lados, vale a ordem do local, com os itens novos do remote no fim")
    func bothReorderedKeepsLocalOrder() throws {
        let base = list([section(1, "A", [entry(11, "x"), entry(12, "y"), entry(13, "z")])])
        let local = list([section(1, "A", [entry(12, "y"), entry(11, "x"), entry(13, "z")])])
        let remote = list([section(1, "A", [entry(13, "z"), entry(12, "y"), entry(11, "x"), entry(14, "n")])])
        let merged = try #require(ChecklistMerge.merge(base: base, local: local, remote: remote))
        #expect(outline(merged) == ["A: y, x, z, n"])
    }

    @Test("A ordem de cada seção é decidida à parte, e o que só o outro lado tem vai para o fim")
    func eachSectionHasItsOwnOrder() throws {
        let base = list([section(1, "A", [entry(11, "x"), entry(12, "y")]), section(2, "B", [entry(21, "p"), entry(22, "q")])])
        // O local reordena só a B e acrescenta o m na A. O remote reordena só a A e acrescenta o n na B.
        let local = list([
            section(1, "A", [entry(11, "x"), entry(12, "y"), entry(13, "m")]), section(2, "B", [entry(22, "q"), entry(21, "p")]),
        ])
        let remote = list([
            section(1, "A", [entry(12, "y"), entry(11, "x")]), section(2, "B", [entry(21, "p"), entry(22, "q"), entry(23, "n")]),
        ])
        let merged = try #require(ChecklistMerge.merge(base: base, local: local, remote: remote))
        #expect(outline(merged) == ["A: y, x, m", "B: q, p, n"])
    }

    @Test("Na ordem só contam os ids que o lado e a base têm em comum: apagar ou acrescentar um item não reordena")
    func reorderIgnoresIDsOnlyOneSideHas() throws {
        let base = list([section(1, "A", [entry(11, "x"), entry(12, "y"), entry(13, "z")])])
        // O local apaga o y e acrescenta o n no começo, sem mexer na ordem dos outros; o remote reordena.
        let local = list([section(1, "A", [entry(14, "n"), entry(11, "x"), entry(13, "z")])])
        let remote = list([section(1, "A", [entry(13, "z"), entry(12, "y"), entry(11, "x")])])
        let merged = try #require(ChecklistMerge.merge(base: base, local: local, remote: remote))
        #expect(outline(merged) == ["A: z, x, n"])
    }

    @Test("Só o remote reordenou as seções: vale a ordem dele, e as seções novas do local ficam no fim")
    func remoteSectionOrderWins() throws {
        let base = list([section(1, "A", [entry(11, "x")]), section(2, "B", [entry(21, "y")]), section(3, "C", [entry(31, "z")])])
        let local = list([
            section(1, "A", [entry(11, "x")]), section(2, "B", [entry(21, "y", done: true)]), section(3, "C", [entry(31, "z")]),
            section(4, "D", [entry(41, "w")]),
        ])
        let remote = list([section(3, "C", [entry(31, "z")]), section(1, "A", [entry(11, "x")]), section(2, "B", [entry(21, "y")])])
        let merged = try #require(ChecklistMerge.merge(base: base, local: local, remote: remote))
        #expect(outline(merged) == ["C: z", "A: x", "B: ✓ y", "D: w"])
    }

    @Test("Só o local reordenou as seções: vale a ordem dele, e as seções novas do remote ficam no fim")
    func localSectionOrderWins() throws {
        let base = list([section(1, "A", [entry(11, "x")]), section(2, "B", [entry(21, "y")])])
        let local = list([section(2, "B", [entry(21, "y")]), section(1, "A", [entry(11, "x")])])
        let remote = list([
            section(1, "A", [entry(11, "x", done: true)]), section(2, "B", [entry(21, "y")]), section(3, "C", [entry(31, "z")]),
        ])
        let merged = try #require(ChecklistMerge.merge(base: base, local: local, remote: remote))
        #expect(outline(merged) == ["B: y", "A: ✓ x", "C: z"])
    }

    @Test("Item do local cuja seção saiu segue para a seção que o remote deu a ele")
    func entryWhoseSectionLeftFollowsRemote() throws {
        let base = list([section(1, "A", [entry(11, "x")]), section(2, "B", [entry(21, "y")])])
        let local = list([section(1, "A", [entry(11, "x"), entry(12, "n")]), section(2, "B", [entry(21, "y")])])
        // O remote apaga a seção A e leva o x para B.
        let remote = list([section(2, "B", [entry(21, "y"), entry(11, "x")])])
        let merged = try #require(ChecklistMerge.merge(base: base, local: local, remote: remote))
        #expect(outline(merged) == ["B: y, x, n"])
    }

    @Test("Id repetido no local (dado corrompido) não duplica o item")
    func duplicatedIDIsKeptOnce() throws {
        let base = list([section(1, "A", [entry(11, "x")]), section(2, "B")])
        let local = list([section(1, "A", [entry(11, "x")]), section(2, "B", [entry(11, "x")])])
        let merged = try #require(ChecklistMerge.merge(base: base, local: local, remote: base))
        #expect(entryIDs(merged) == [id(11)])
    }

    // MARK: Título e abertura

    @Test("Título da lista: vale o lado que mudou e, mudado dos dois jeitos, o do local")
    func listTitle() throws {
        let sections = [section(1, "Mercado")]
        func merged(local: String, remote: String) throws -> String {
            try #require(
                ChecklistMerge.merge(
                    base: list(sections, title: "Compras"), local: list(sections, title: local), remote: list(sections, title: remote))
            ).title
        }
        #expect(try merged(local: "Compras da semana", remote: "Compras") == "Compras da semana")
        #expect(try merged(local: "Compras", remote: "Feira") == "Feira")
        #expect(try merged(local: "Compras da semana", remote: "Feira") == "Compras da semana")
        #expect(try merged(local: "Feira", remote: "Feira") == "Feira")
    }

    @Test("Abertura: parágrafos diferentes entram nos dois lados; o mesmo trecho dos dois lados faz a lista toda ser conflito")
    func intro() throws {
        let sections = [section(1, "Mercado", [entry(11, "leite")])]
        let base = list(sections, intro: "Primeiro.\n\nSegundo.")
        let local = list(sections, intro: "Primeiro, revisado.\n\nSegundo.")
        let remote = list(sections, intro: "Primeiro.\n\nSegundo, revisado.")
        let merged = try #require(ChecklistMerge.merge(base: base, local: local, remote: remote))
        #expect(merged.intro == "Primeiro, revisado.\n\nSegundo, revisado.")

        // Os itens se juntariam sem problema, mas a abertura colide.
        let localSame = list(sections, intro: "Primeiro aqui.\n\nSegundo.")
        let remoteSame = list([section(1, "Mercado", [entry(11, "leite", done: true)])], intro: "Primeiro lá.\n\nSegundo.")
        #expect(ChecklistMerge.merge(base: base, local: localSame, remote: remoteSame) == nil)
    }

    // MARK: Sorteios

    @Test("Sorteios com semente fixa: um lado só que mexeu vale inteiro, e com os dois nenhum id se repete nem se perde")
    func randomizedProperties() {
        var generator = SeededGenerator(seed: 2026)
        var merged = 0
        for round in 0..<400 {
            let base = randomList(using: &generator)
            let local = edited(base, idBase: 100, appendOnly: false, using: &generator)
            let remote = edited(base, idBase: 200, appendOnly: false, using: &generator)

            // Só um lado mexeu: a lista é a dele. Do remote só entra, no fim, o que ele acrescenta, que é o que a junção também faz.
            #expect(ChecklistMerge.merge(base: base, local: local, remote: base) == local, "rodada \(round): só o local mexeu")
            let appended = edited(base, idBase: 200, appendOnly: true, using: &generator)
            #expect(ChecklistMerge.merge(base: base, local: base, remote: appended) == appended, "rodada \(round): só o remote mexeu")

            // Os dois mexeram: sem conflito, nenhum id se repete e nenhum item novo se perde.
            guard let result = ChecklistMerge.merge(base: base, local: local, remote: remote) else { continue }
            merged += 1
            let ids = entryIDs(result)
            #expect(ids.count == Set(ids).count, "rodada \(round): item repetido")
            #expect(result.sections.map(\.id).count == Set(result.sections.map(\.id)).count, "rodada \(round): seção repetida")
            let known = Set(entryIDs(local) + entryIDs(remote))
            #expect(Set(ids).isSubset(of: known), "rodada \(round): item que nenhum dos lados tem")
            #expect(known.subtracting(entryIDs(base)).isSubset(of: Set(ids)), "rodada \(round): item novo perdido")
            #expect(ChecklistMerge.merge(base: base, local: local, remote: remote) == result, "rodada \(round): resultado instável")
        }
        // Os sorteios passam de verdade pela junção dos dois lados, e não só por conflitos.
        #expect(merged > 100)
    }
}
