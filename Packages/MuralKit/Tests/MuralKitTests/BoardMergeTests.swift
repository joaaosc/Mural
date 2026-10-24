import Foundation
import Testing

@testable import MuralKit

// MARK: Fixtures

/// Ids fixos e legíveis: `id(3)` é sempre o mesmo, e a ordem do `uuidString` segue a do número.
private func id(_ number: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012ld", number))!
}

private func date(_ seconds: Double) -> Date {
    Date(timeIntervalSince1970: seconds)
}

/// O "agora" das cópias de conflito: o teste sabe a data que elas ganham.
private let now = date(5_000)

private let corner = BoardPoint(x: 100, y: 100)

private func board(_ items: [BoardItem], freeTexts: [BoardFreeText] = []) -> Board {
    Board(items: items, freeTexts: freeTexts)
}

private func note(_ number: Int, text: String? = nil, in parent: Int? = nil, at position: BoardPoint = corner) -> BoardItem {
    BoardItem(
        id: id(number), kind: .text, title: "Nota \(number)", createdAt: date(Double(number)), parentID: parent.map(id),
        position: position, text: text)
}

private func sticky(_ number: Int, text: String, in parent: Int? = nil, folderPosition: BoardPoint? = nil) -> BoardItem {
    BoardItem(
        id: id(number), kind: .sticky, title: text, createdAt: date(Double(number)), parentID: parent.map(id), position: corner,
        text: text, folderPosition: folderPosition)
}

/// O post-it depois de editado, como `BoardModel.updateSticky` o deixa: o título acompanha o texto.
private func editedSticky(_ item: BoardItem, text: String) -> BoardItem {
    var edited = item
    edited.text = text
    edited.title = ContentClassifier.title(forText: text)
    return edited
}

private func folder(_ number: Int) -> BoardItem {
    BoardItem(id: id(number), kind: .folder, title: "Pasta \(number)", createdAt: date(Double(number)), position: corner)
}

/// Um cartão de lista com uma seção "Mercado" e os itens dados; cada item é (id, texto, marcado).
private func shoppingCard(_ number: Int, _ entries: [(Int, String, Bool)]) -> BoardItem {
    let section = ChecklistSection(
        id: id(900), title: "Mercado", entries: entries.map { ChecklistEntry(id: id($0.0), text: $0.1, isDone: $0.2) })
    return BoardItem(
        id: id(number), kind: .checklist, title: "Compras", createdAt: date(Double(number)), position: corner,
        checklist: ChecklistDocument(title: "Compras", sections: [section]))
}

private func freeText(_ number: Int, _ text: String, at position: BoardPoint = BoardPoint(x: 50, y: 50)) -> BoardFreeText {
    BoardFreeText(id: id(number), text: text, position: position, createdAt: date(Double(number)))
}

private func shared(_ item: BoardItem) -> BoardItem {
    SharedFieldPolicy.shared(item)
}

private let noteText = "A visita é na segunda. Medir a parede norte.\n\nUma frase só."

/// Frases curtas que valem para `source`.
private func record(for source: String) -> KeySentenceRecord {
    KeySentenceRecord(source: source, choices: [:])
}

/// Um link com os arquivos da prévia e o estado da busca, as partes locais.
private func fullLink(_ address: String = "https://apple.com/mac") -> LinkInfo {
    LinkInfo(
        url: URL(string: address)!, pageTitle: "Mac", siteName: "Apple", summary: "Resumo", previewImageFile: "A1B2.jpg",
        iconFile: "C3D4.png", preview: .ready(fetchedAt: date(1_000)))
}

private func linkCard(_ number: Int, _ link: LinkInfo) -> BoardItem {
    BoardItem(id: id(number), kind: .link, title: "Mac", createdAt: date(Double(number)), position: corner, link: link)
}

private func attachment(_ name: String) -> NoteAttachment {
    NoteAttachment(fileName: name, pixelWidth: 10, pixelHeight: 10)
}

private func apply(_ remote: RemoteBoardChanges, to local: Board, base: Board) -> BoardMergeResult {
    BoardMerge.apply(remote, to: local, base: base, now: now)
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

/// Um mural, o que o iCloud conhecia dele e o que chegou, sorteados sem cuidado nenhum de manter tudo coerente: cartões que somem
/// dos dois lados, pais que não existem, pastas dentro de si mesmas, ids gravados e apagados juntos. A junção precisa dar conta.
private func randomScenario(using generator: inout SeededGenerator) -> (base: Board, local: Board, remote: RemoteBoardChanges) {
    func chance(_ outOf: Int) -> Bool { Int.random(in: 0..<outOf, using: &generator) == 0 }
    let parents: [UUID?] = [nil, id(1), id(2), id(99)]
    func randomParent() -> UUID? { parents.randomElement(using: &generator)! }

    var baseItems = [folder(1), folder(2)]
    for number in 3...8 {
        var item = number >= 7 ? sticky(number, text: "t\(number)") : note(number, text: "t\(number)")
        item.parentID = randomParent()
        baseItems.append(item)
    }
    baseItems[1].parentID = chance(2) ? id(1) : nil

    func edited(_ item: BoardItem, _ label: String) -> BoardItem {
        var copy = item
        if copy.kind != .folder, chance(2) { copy.text = "\(label) \(number(of: item))" }
        if chance(3) { copy.position = BoardPoint(x: Double(Int.random(in: 0..<500, using: &generator)), y: 50) }
        if chance(3) { copy.colorTag = TagColor.allCases.randomElement(using: &generator) }
        if chance(4) { copy.parentID = randomParent() }
        return copy
    }
    func number(of item: BoardItem) -> String { String(item.id.uuidString.suffix(2)) }

    var localItems = baseItems.filter { _ in !chance(6) }.map { edited($0, "daqui") }
    if chance(2) { localItems.append(note(30, text: "novo daqui", in: nil)) }
    var saved = baseItems.filter { _ in chance(2) }.map { edited($0, "de lá") }
    if chance(2) { saved.append(BoardItem(id: id(40), kind: .text, title: "Novo", parentID: randomParent(), text: "novo de lá")) }
    let deleted = Set(baseItems.map(\.id).filter { _ in chance(6) })
    var layers: [UUID: Double] = [:]
    for item in baseItems + saved where chance(2) { layers[item.id] = Double(Int.random(in: 0..<10, using: &generator)) }

    let remote = RemoteBoardChanges(savedItems: saved, deletedItemIDs: deleted, layers: layers)
    return (board(baseItems), board(localItems), remote)
}

// MARK: Um cartão

@Suite("Junção de um cartão")
struct MergeItemTests {
    // MARK: Campo a campo

    @Test("Sem base, vale o local em tudo e não nasce cópia")
    func withoutBaseLocalWins() {
        var local = note(1, text: "daqui", at: BoardPoint(x: 10, y: 10))
        local.colorTag = .red
        local.keySentences = record(for: "daqui")
        var remote = note(1, text: "de lá", at: BoardPoint(x: 90, y: 90))
        remote.colorTag = .blue

        let result = BoardMerge.mergeItem(base: nil, local: local, remote: remote, now: now)
        #expect(result.merged == local)
        #expect(result.conflictCopy == nil)
    }

    @Test("Campo que o local não mudou vale o do remote, que o remote não mudou vale o do local, e mudado igual vale o valor")
    func fieldByField() {
        let base = note(1, text: "texto")
        var local = base
        local.title = "Título daqui"
        local.tag = "CLIENTE"
        var remote = base
        remote.colorTag = .blue
        remote.tag = "CLIENTE"

        let result = BoardMerge.mergeItem(base: base, local: local, remote: remote, now: now)
        #expect(result.merged.title == "Título daqui")
        #expect(result.merged.colorTag == .blue)
        #expect(result.merged.tag == "CLIENTE")
        #expect(result.merged.text == "texto")
        #expect(result.conflictCopy == nil)
    }

    @Test("Posição, legenda e cor mudadas dos dois jeitos ficam como no local")
    func otherFieldsKeepLocal() {
        let base = note(1, text: "texto")
        var local = base
        local.position = BoardPoint(x: 200, y: 200)
        local.caption = "legenda daqui"
        local.colorTag = .red
        var remote = base
        remote.position = BoardPoint(x: 300, y: 300)
        remote.caption = "legenda de lá"
        remote.colorTag = .blue
        remote.tag = "SÓ LÁ"

        let result = BoardMerge.mergeItem(base: base, local: local, remote: remote, now: now)
        #expect(result.merged.position == BoardPoint(x: 200, y: 200))
        #expect(result.merged.caption == "legenda daqui")
        #expect(result.merged.colorTag == .red)
        #expect(result.merged.tag == "SÓ LÁ", "o campo que só o remote mudou entra")
        #expect(result.conflictCopy == nil)
    }

    @Test("O tamanho do post-it mudado só lá entra; mudado dos dois jeitos, fica o daqui")
    func stickySizeFollowsTheFieldRule() {
        let base = sticky(1, text: "Tinta")
        var remote = base
        remote.size = BoardSize(width: 300, height: 200)

        let onlyThere = BoardMerge.mergeItem(base: base, local: base, remote: remote, now: now)
        #expect(onlyThere.merged.size == BoardSize(width: 300, height: 200))

        var local = base
        local.size = BoardSize(width: 150, height: 150)
        let both = BoardMerge.mergeItem(base: base, local: local, remote: remote, now: now)
        #expect(both.merged.size == BoardSize(width: 150, height: 150))
        #expect(both.conflictCopy == nil)
    }

    // MARK: Texto

    @Test("Texto editado em parágrafos diferentes: os dois entram, sem cópia")
    func textParagraphsMerge() {
        let base = note(1, text: "Primeiro.\n\nSegundo.")
        var local = base
        local.text = "Primeiro, revisado.\n\nSegundo."
        var remote = base
        remote.text = "Primeiro.\n\nSegundo, revisado."

        let result = BoardMerge.mergeItem(base: base, local: local, remote: remote, now: now)
        #expect(result.merged.text == "Primeiro, revisado.\n\nSegundo, revisado.")
        #expect(result.conflictCopy == nil)
    }

    @Test("Texto nulo conta como vazio, e um resultado vazio volta a ser nulo")
    func emptyTextBecomesNil() {
        let base = note(1, text: "a")
        var local = base
        local.text = nil
        var remote = base
        remote.text = ""

        let result = BoardMerge.mergeItem(base: base, local: local, remote: remote, now: now)
        #expect(result.merged.text == nil)
        #expect(result.conflictCopy == nil)
    }

    @Test("Texto editado na mesma linha: o cartão fica com o texto do remote e a cópia leva o do local")
    func textCollisionMakesACopy() throws {
        let base = note(1, text: "Linha única.")
        var local = base
        local.text = "Linha daqui."
        local.colorTag = .red
        var remote = base
        remote.text = "Linha de lá."

        let result = BoardMerge.mergeItem(base: base, local: local, remote: remote, now: now)
        #expect(result.merged.text == "Linha de lá.")
        #expect(result.merged.colorTag == .red, "o resto do cartão segue as regras de sempre")
        #expect(result.merged.id == id(1))

        let copy = try #require(result.conflictCopy)
        #expect(copy.id != id(1))
        #expect(copy.text == "Linha daqui.")
        #expect(copy.colorTag == .red)
        #expect(copy.kind == .text)
        #expect(copy.createdAt == now)
        #expect(copy.title == "Nota 1 (cópia de conflito)")
        #expect(copy.parentID == nil)
        #expect(copy.position == BoardPoint(x: 124, y: 124))
    }

    // MARK: Cópia de conflito

    @Test("A cópia solta no mural desloca a posição e a mantém dentro do mural, arredondada")
    func copyPositionIsShiftedAndClamped() throws {
        let base = note(1, text: "a")
        var local = base
        local.text = "b"
        local.position = BoardPoint(x: 10.4, y: 20.6)
        var remote = base
        remote.text = "c"

        let copy = try #require(BoardMerge.mergeItem(base: base, local: local, remote: remote, now: now).conflictCopy)
        #expect(copy.position == BoardPoint(x: 34, y: 45))
    }

    @Test("A cópia de um post-it numa pasta fica na mesma pasta, com o título como está e o lugar livre deslocado")
    func stickyCopyStaysInTheFolder() throws {
        let base = sticky(1, text: "Comprar pão", in: 9, folderPosition: BoardPoint(x: 20, y: 30))
        let local = editedSticky(base, text: "Comprar pão e leite")
        let remote = editedSticky(base, text: "Comprar pão integral")

        let result = BoardMerge.mergeItem(base: base, local: local, remote: remote, now: now)
        #expect(result.merged.text == "Comprar pão integral")
        let copy = try #require(result.conflictCopy)
        #expect(copy.text == "Comprar pão e leite")
        #expect(copy.title == "Comprar pão e leite", "o título de um post-it segue o texto: fica como está")
        #expect(copy.parentID == id(9))
        #expect(copy.folderPosition == BoardPoint(x: 44, y: 54))
        #expect(copy.position == corner, "dentro de uma pasta a posição no mural não conta")
    }

    // MARK: Título do post-it

    @Test("Texto de post-it em colisão: o título acompanha o texto que ficou, e não o título do local")
    func stickyTitleFollowsTheCollidedText() {
        let base = sticky(1, text: "Comprar pão")
        let local = editedSticky(base, text: "Comprar pão e leite")
        let remote = editedSticky(base, text: "Comprar pão integral")

        let result = BoardMerge.mergeItem(base: base, local: local, remote: remote, now: now)
        #expect(result.merged.text == "Comprar pão integral")
        #expect(result.merged.title == "Comprar pão integral")
    }

    @Test("Texto de post-it juntado: o título é a primeira linha do texto junto, mesmo que o título antigo estivesse desatualizado")
    func stickyTitleFollowsTheMergedText() {
        var base = sticky(1, text: "a\n\nb")
        base.title = "título antigo"
        var local = base
        local.text = "A\n\nb"
        var remote = base
        remote.text = "a\n\nB"

        let result = BoardMerge.mergeItem(base: base, local: local, remote: remote, now: now)
        #expect(result.merged.text == "A\n\nB")
        #expect(result.merged.title == "A")
        #expect(result.conflictCopy == nil)
    }

    @Test("Post-it que fica sem texto na junção fica sem título")
    func stickyWithoutTextHasNoTitle() {
        let base = sticky(1, text: "a")
        var local = base
        local.text = nil
        var remote = base
        remote.text = ""

        let result = BoardMerge.mergeItem(base: base, local: local, remote: remote, now: now)
        #expect(result.merged.text == nil)
        #expect(result.merged.title == "")
    }

    @Test("Post-it com o texto mudado só de um lado segue os campos: o título que veio com o texto")
    func stickyTitleFollowsTheFieldsWhenTheTextChangedOnOneSide() {
        let base = sticky(1, text: "Comprar pão")
        let local = editedSticky(base, text: "Comprar pão e leite")
        var remote = base
        remote.colorTag = .green

        let result = BoardMerge.mergeItem(base: base, local: local, remote: remote, now: now)
        #expect(result.merged.text == "Comprar pão e leite")
        #expect(result.merged.title == "Comprar pão e leite")
        #expect(result.merged.colorTag == .green)
    }

    @Test("Nota e lista continuam com o título pela regra dos campos, mesmo com o texto ou a lista em colisão")
    func noteAndChecklistTitleKeepTheFieldRule() {
        let baseNote = note(1, text: "Linha única.")
        var localNote = baseNote
        localNote.text = "Linha daqui."
        localNote.title = "Título daqui"
        var remoteNote = baseNote
        remoteNote.text = "Linha de lá."
        let noteResult = BoardMerge.mergeItem(base: baseNote, local: localNote, remote: remoteNote, now: now)
        #expect(noteResult.merged.text == "Linha de lá.")
        #expect(noteResult.merged.title == "Título daqui")

        let card = shoppingCard(2, [(11, "leite", false)])
        var localCard = shoppingCard(2, [(11, "leite integral", false)])
        localCard.title = "Compras da semana"
        let remoteCard = shoppingCard(2, [(11, "leite desnatado", false)])
        let cardResult = BoardMerge.mergeItem(base: card, local: localCard, remote: remoteCard, now: now)
        #expect(cardResult.merged.checklist == remoteCard.checklist)
        #expect(cardResult.merged.title == "Compras da semana")
    }

    @Test("A cópia leva o conteúdo do local na forma compartilhada, sem as partes locais")
    func copyHasNoLocalParts() throws {
        let base = note(1, text: noteText)
        var local = base
        local.text = noteText + "\nDaqui."
        local.keySentences = record(for: noteText + "\nDaqui.")
        var remote = base
        remote.text = noteText + "\nDe lá."

        let copy = try #require(BoardMerge.mergeItem(base: base, local: local, remote: remote, now: now).conflictCopy)
        #expect(copy.keySentences == nil)
    }

    // MARK: Lista

    @Test("Lista de compras: as marcações de itens diferentes entram juntas, sem cópia")
    func checklistMerges() throws {
        let base = shoppingCard(1, [(11, "leite", false), (12, "pão", false)])
        let local = shoppingCard(1, [(11, "leite", true), (12, "pão", false)])
        let remote = shoppingCard(1, [(11, "leite", false), (12, "pão", true)])

        let result = BoardMerge.mergeItem(base: base, local: local, remote: remote, now: now)
        #expect(result.merged.checklist == shoppingCard(1, [(11, "leite", true), (12, "pão", true)]).checklist)
        #expect(result.conflictCopy == nil)
    }

    @Test("Lista com o texto do mesmo item editado dos dois jeitos: a lista do remote fica e a cópia leva a do local")
    func checklistCollisionMakesACopy() throws {
        let base = shoppingCard(1, [(11, "leite", false)])
        let local = shoppingCard(1, [(11, "leite integral", false)])
        let remote = shoppingCard(1, [(11, "leite desnatado", false)])

        let result = BoardMerge.mergeItem(base: base, local: local, remote: remote, now: now)
        #expect(result.merged.checklist == remote.checklist)
        let copy = try #require(result.conflictCopy)
        #expect(copy.checklist == local.checklist)
        #expect(copy.kind == .checklist)
        #expect(copy.title == "Compras (cópia de conflito)")
    }

    @Test("Lista que um dos lados não tem mais: a lista do remote fica e a cópia leva o que o local tinha")
    func checklistMissingOnOneSide() throws {
        let base = shoppingCard(1, [(11, "leite", false)])
        var removedHere = base
        removedHere.checklist = nil
        let editedThere = shoppingCard(1, [(11, "leite", true)])

        let result = BoardMerge.mergeItem(base: base, local: removedHere, remote: editedThere, now: now)
        #expect(result.merged.checklist == editedThere.checklist)
        let copy = try #require(result.conflictCopy)
        #expect(copy.checklist == nil)
    }

    // MARK: Anexos

    @Test("Anexos mudados dos dois lados se somam pelo nome do arquivo: primeiro os do remote, depois os que só o local tem")
    func attachmentsAreUnited() {
        var base = note(1, text: "a")
        base.attachments = [attachment("a.png")]
        var local = base
        local.attachments = [attachment("a.png"), attachment("b.png")]
        var remote = base
        remote.attachments = [attachment("c.png"), attachment("a.png")]

        let result = BoardMerge.mergeItem(base: base, local: local, remote: remote, now: now)
        #expect(result.merged.attachments?.map(\.fileName) == ["c.png", "a.png", "b.png"])
        #expect(result.conflictCopy == nil)
    }

    @Test("Anexos que ficam vazios nos dois lados voltam a ser nulos")
    func emptyAttachmentsBecomeNil() {
        var base = note(1, text: "a")
        base.attachments = [attachment("a.png")]
        var local = base
        local.attachments = []
        var remote = base
        remote.attachments = nil

        let result = BoardMerge.mergeItem(base: base, local: local, remote: remote, now: now)
        #expect(result.merged.attachments == nil)
    }

    // MARK: Partes locais

    @Test("O resultado guarda as frases curtas e os arquivos da prévia do cartão local")
    func localPartsAreKept() {
        let base = shared(linkCard(1, fullLink()))
        var local = linkCard(1, fullLink())
        local.position = BoardPoint(x: 300, y: 300)
        local.keySentences = record(for: "não usado")
        var remote = base
        remote.colorTag = .green

        let result = BoardMerge.mergeItem(base: base, local: local, remote: remote, now: now)
        #expect(result.merged.link == fullLink(), "arquivos e estado da prévia do local, no mesmo endereço")
        #expect(result.merged.colorTag == .green)
        #expect(result.merged.position == BoardPoint(x: 300, y: 300))
        #expect(result.merged.keySentences == nil, "um link não tem texto que as frases curtas valham")
    }
}

// MARK: O mural

@Suite("Junção do mural")
struct BoardMergeTests {
    // MARK: Cartões do remote

    @Test("Cartão novo de outra pessoa entra no fim da lista, sem partes locais")
    func newRemoteItemEnters() {
        let existing = note(1, text: "daqui")
        var arrived = note(7, text: "chegou")
        arrived.keySentences = record(for: "chegou")

        let remote = RemoteBoardChanges(savedItems: [arrived])
        let result = apply(remote, to: board([existing]), base: board([existing]))
        #expect(result.board.items.map(\.id) == [id(1), id(7)])
        #expect(result.board.item(id: id(7)) == shared(arrived))
        #expect(result.conflictCopies.isEmpty)
        #expect(result.repairedItemIDs.isEmpty)
    }

    @Test("Edição remota sem edição local vale o que chegou")
    func remoteEditWithoutLocalEdit() {
        let base = note(1, text: "antes")
        var edited = base
        edited.text = "depois"
        edited.colorTag = .red

        let result = apply(RemoteBoardChanges(savedItems: [edited]), to: board([base]), base: board([base]))
        #expect(result.board.items == [edited])
        #expect(result.conflictCopies.isEmpty)
    }

    @Test("Posição mudada dos dois lados fica a do local, e o resto que chegou entra")
    func positionChangedOnBothSides() {
        let base = note(1, text: "texto")
        var local = base
        local.position = BoardPoint(x: 200, y: 200)
        var remote = base
        remote.position = BoardPoint(x: 300, y: 300)
        remote.colorTag = .blue

        let result = apply(RemoteBoardChanges(savedItems: [remote]), to: board([local]), base: board([base]))
        let merged = result.board.item(id: id(1))
        #expect(merged?.position == BoardPoint(x: 200, y: 200))
        #expect(merged?.colorTag == .blue)
        #expect(result.conflictCopies.isEmpty)
    }

    @Test("Título mudado aqui e cor mudada lá: os dois entram")
    func localTitleAndRemoteColor() {
        let base = note(1, text: "texto")
        var local = base
        local.title = "Título daqui"
        var remote = base
        remote.colorTag = .purple

        let result = apply(RemoteBoardChanges(savedItems: [remote]), to: board([local]), base: board([base]))
        let merged = result.board.item(id: id(1))
        #expect(merged?.title == "Título daqui")
        #expect(merged?.colorTag == .purple)
    }

    @Test("Nota com parágrafos diferentes editados: o texto sai junto, sem cópia")
    func noteParagraphsMerge() {
        let base = note(1, text: "Primeiro.\n\nSegundo.")
        var local = base
        local.text = "Primeiro, revisado.\n\nSegundo."
        var remote = base
        remote.text = "Primeiro.\n\nSegundo, revisado."

        let result = apply(RemoteBoardChanges(savedItems: [remote]), to: board([local]), base: board([base]))
        #expect(result.board.items.count == 1)
        #expect(result.board.item(id: id(1))?.text == "Primeiro, revisado.\n\nSegundo, revisado.")
        #expect(result.conflictCopies.isEmpty)
    }

    @Test("Nota editada na mesma linha: o cartão fica com o texto do remote e uma cópia leva o do local")
    func noteSameLineMakesACopy() throws {
        let base = note(1, text: "Linha única.")
        var local = base
        local.text = "Linha daqui."
        var remote = base
        remote.text = "Linha de lá."

        let result = apply(RemoteBoardChanges(savedItems: [remote]), to: board([local]), base: board([base]))
        #expect(result.board.items.count == 2)
        #expect(result.board.items[0].id == id(1))
        #expect(result.board.items[0].text == "Linha de lá.")
        let copy = result.board.items[1]
        #expect(copy.text == "Linha daqui.")
        #expect(copy.createdAt == now)
        #expect(result.conflictCopies == [copy.id: id(1)])
    }

    @Test("Lista de compras: as marcações de pessoas diferentes ficam juntas no mesmo cartão")
    func shoppingListMerges() {
        let base = shoppingCard(1, [(11, "leite", false), (12, "pão", false)])
        let local = shoppingCard(1, [(11, "leite", true), (12, "pão", false)])
        let remote = shoppingCard(1, [(11, "leite", false), (12, "pão", true)])

        let result = apply(RemoteBoardChanges(savedItems: [remote]), to: board([local]), base: board([base]))
        #expect(result.board.items.count == 1)
        #expect(result.board.items[0].checklist == shoppingCard(1, [(11, "leite", true), (12, "pão", true)]).checklist)
        #expect(result.conflictCopies.isEmpty)
    }

    // MARK: Apagados

    @Test("Apagado lá e nota editada aqui: o original sai e uma cópia leva o que foi escrito aqui")
    func remoteDeletedLocalEdited() {
        let base = note(1, text: "antes")
        var local = base
        local.text = "antes e depois"

        let result = apply(RemoteBoardChanges(deletedItemIDs: [id(1)]), to: board([local]), base: board([base]))
        #expect(result.board.items.count == 1)
        let copy = result.board.items[0]
        #expect(copy.id != id(1))
        #expect(copy.text == "antes e depois")
        #expect(copy.title == "Nota 1 (cópia de conflito)")
        #expect(copy.createdAt == now)
        #expect(result.conflictCopies == [copy.id: id(1)])
    }

    @Test("Apagado lá e só movido aqui: o cartão sai, sem cópia")
    func remoteDeletedLocalMoved() {
        let base = note(1, text: "texto")
        var local = base
        local.position = BoardPoint(x: 400, y: 400)
        let other = note(2, text: "fica")

        let result = apply(
            RemoteBoardChanges(deletedItemIDs: [id(1)]), to: board([local, other]), base: board([base, other]))
        #expect(result.board.items == [other])
        #expect(result.conflictCopies.isEmpty)
    }

    @Test("Apagado aqui e nota editada lá: não volta, e o que chegou entra como cópia")
    func localDeletedRemoteEdited() {
        let base = note(1, text: "antes")
        var remote = base
        remote.text = "antes e depois"

        let result = apply(RemoteBoardChanges(savedItems: [remote]), to: board([]), base: board([base]))
        #expect(result.board.items.count == 1)
        let copy = result.board.items[0]
        #expect(copy.id != id(1))
        #expect(copy.text == "antes e depois")
        #expect(copy.title == "Nota 1 (cópia de conflito)")
        #expect(result.conflictCopies == [copy.id: id(1)])
    }

    @Test("Apagado aqui e só a cor mudada lá: continua apagado, sem cópia")
    func localDeletedRemoteRecolored() {
        let base = note(1, text: "texto")
        var remote = base
        remote.colorTag = .red

        let result = apply(RemoteBoardChanges(savedItems: [remote]), to: board([]), base: board([base]))
        #expect(result.board.items.isEmpty)
        #expect(result.conflictCopies.isEmpty)
    }

    @Test("Pasta apagada lá enquanto aqui entrou um cartão nela: o cartão vai para o mural")
    func cardInDeletedFolderGoesToTheBoard() {
        let base = board([folder(1)])
        let local = board([folder(1), note(2, text: "criada aqui", in: 1)])

        let result = apply(RemoteBoardChanges(deletedItemIDs: [id(1)]), to: local, base: base)
        #expect(result.board.items.map(\.id) == [id(2)])
        #expect(result.board.item(id: id(2))?.parentID == nil)
        #expect(result.repairedItemIDs == [id(2)])
    }

    @Test("Pasta apagada lá com os filhos: o filho editado aqui vira uma cópia solta no mural")
    func editedChildOfDeletedFolderBecomesACopy() {
        let base = board([folder(1), note(2, text: "antes", in: 1)])
        let local = board([folder(1), note(2, text: "antes e depois", in: 1)])

        let result = apply(RemoteBoardChanges(deletedItemIDs: [id(1), id(2)]), to: local, base: base)
        #expect(result.board.items.count == 1)
        let copy = result.board.items[0]
        #expect(copy.text == "antes e depois")
        #expect(copy.parentID == nil)
        #expect(result.repairedItemIDs == [copy.id])
        #expect(result.conflictCopies == [copy.id: id(2)])
    }

    @Test("Um id gravado e apagado ao mesmo tempo vale como apagado")
    func deletedWinsOverSaved() {
        let base = note(1, text: "texto")
        var remote = base
        remote.colorTag = .red

        let result = apply(
            RemoteBoardChanges(savedItems: [remote], deletedItemIDs: [id(1)]), to: board([base]), base: board([base]))
        #expect(result.board.items.isEmpty)
    }

    // MARK: Ordem

    @Test("A lista segue os números de empilhamento; quem não tem número fica no fim, na ordem em que estava")
    func orderFollowsLayers() {
        let items = [note(1), note(2), note(3), note(4)]
        let layers: [UUID: Double] = [id(1): 3, id(2): 1, id(3): 2]

        let result = apply(RemoteBoardChanges(layers: layers), to: board(items), base: board(items))
        #expect(result.board.items.map(\.id) == [id(2), id(3), id(1), id(4)])

        // Um cartão novo entra no lugar que o número dele manda.
        var withArrival = layers
        withArrival[id(5)] = 1.5
        let arrival = apply(RemoteBoardChanges(savedItems: [note(5)], layers: withArrival), to: board(items), base: board(items))
        #expect(arrival.board.items.map(\.id) == [id(2), id(5), id(3), id(1), id(4)])
    }

    // MARK: Partes locais

    @Test("Sem nada a enviar daqui, vale o que chegou e as frases curtas e a prévia do link continuam valendo")
    func localPartsSurviveWhenNothingIsPending() {
        var local = note(1, text: noteText)
        local.keySentences = record(for: noteText)
        var recolored = shared(local)
        recolored.colorTag = .red

        let link = linkCard(2, fullLink())
        var retitled = shared(link)
        retitled.title = "Novo título"

        let items = [local, link]
        let base = board(items.map(shared))
        let result = apply(RemoteBoardChanges(savedItems: [recolored, retitled]), to: board(items), base: base)
        #expect(result.board.item(id: id(1))?.colorTag == .red)
        #expect(result.board.item(id: id(1))?.keySentences == record(for: noteText))
        #expect(result.board.item(id: id(2))?.title == "Novo título")
        #expect(result.board.item(id: id(2))?.link == fullLink())
    }

    @Test("As partes locais deixam de valer quando o que chegou muda o texto ou o endereço do link")
    func localPartsDropWhenContentChanges() {
        var local = note(1, text: noteText)
        local.keySentences = record(for: noteText)
        var rewritten = shared(local)
        rewritten.text = "Outro texto."

        let link = linkCard(2, fullLink())
        var moved = shared(link)
        moved.link?.url = URL(string: "https://apple.com/ipad")!

        let items = [local, link]
        let result = apply(RemoteBoardChanges(savedItems: [rewritten, moved]), to: board(items), base: board(items.map(shared)))
        #expect(result.board.item(id: id(1))?.text == "Outro texto.")
        #expect(result.board.item(id: id(1))?.keySentences == nil)
        #expect(result.board.item(id: id(2))?.link?.previewImageFile == nil)
        #expect(result.board.item(id: id(2))?.link?.preview == .pending)
    }

    @Test("Com algo a enviar daqui, a junção também guarda as partes locais")
    func localPartsSurviveTheMerge() {
        var local = note(1, text: noteText)
        local.keySentences = record(for: noteText)
        local.position = BoardPoint(x: 300, y: 300)
        var remote = shared(local)
        remote.position = corner
        remote.colorTag = .orange

        let result = apply(RemoteBoardChanges(savedItems: [remote]), to: board([local]), base: board([note(1, text: noteText)]))
        let merged = result.board.item(id: id(1))
        #expect(merged?.position == BoardPoint(x: 300, y: 300))
        #expect(merged?.colorTag == .orange)
        #expect(merged?.keySentences == record(for: noteText))
    }

    // MARK: Fechamento

    @Test("Sem mudanças do remote o mural volta idêntico ao daqui, até de uma versão antiga do formato")
    func noChangesLeavesTheBoardAlone() {
        let items = [note(1, text: "a"), note(2, text: "b")]
        let local = board(items, freeTexts: [freeText(5, "solto")])
        let result = apply(RemoteBoardChanges(), to: local, base: local)
        #expect(result.board == local)
        #expect(result.conflictCopies.isEmpty)
        #expect(result.repairedItemIDs.isEmpty)

        // Um mural gravado por uma build antiga só muda de versão junto com uma mudança de fato.
        var old = board([note(1, text: "a")])
        old.formatVersion = 0
        let untouched = apply(RemoteBoardChanges(), to: old, base: old)
        #expect(untouched.board == old)
        #expect(untouched.board.formatVersion == 0)
    }

    @Test("Um cartão que chegou igual ao daqui não é mudança: a versão do formato fica")
    func identicalCardIsNotAChange() {
        var old = board([note(1, text: "a")])
        old.formatVersion = 0

        let result = apply(RemoteBoardChanges(savedItems: [note(1, text: "a")], layers: [id(1): 1]), to: old, base: old)
        #expect(result.board == old)
    }

    @Test("A versão do formato passa a ser a que o conteúdo exige quando o mural muda")
    func formatVersionIsRaised() {
        var old = board([note(1, text: "a")])
        old.formatVersion = 0

        let result = apply(RemoteBoardChanges(savedItems: [linkCard(2, fullLink())]), to: old, base: old)
        #expect(result.board.formatVersion == result.board.requiredFormatVersion)
        #expect(result.board.formatVersion >= 3)

        // Um texto livre novo também é mudança.
        let withFreeText = apply(RemoteBoardChanges(savedFreeTexts: [freeText(2, "chegou")]), to: old, base: old)
        #expect(withFreeText.board.formatVersion == 7)

        // E a ordem de empilhamento, mesmo sozinha.
        var twoNotes = board([note(1), note(2)])
        twoNotes.formatVersion = 0
        let reordered = apply(RemoteBoardChanges(layers: [id(1): 2, id(2): 1]), to: twoNotes, base: twoNotes)
        #expect(reordered.board.items.map(\.id) == [id(2), id(1)])
        #expect(reordered.board.formatVersion == reordered.board.requiredFormatVersion)
    }

    @Test("Ids repetidos no que chegou valem uma vez só, com a última gravação")
    func repeatedSavedIDsCountOnce() {
        var first = note(7, text: "primeira")
        first.colorTag = .red
        let second = note(7, text: "segunda")

        let result = apply(RemoteBoardChanges(savedItems: [first, second]), to: board([]), base: board([]))
        #expect(result.board.items == [second])
    }

    // MARK: Sorteios

    @Test("Sorteios com semente fixa: ids únicos, pais válidos, versão do formato certa e nenhum texto perdido, seja qual for a combinação")
    func randomizedInvariants() {
        var generator = SeededGenerator(seed: 2026)
        var copies = 0
        var repaired = 0
        for round in 0..<300 {
            let scenario = randomScenario(using: &generator)
            let result = apply(scenario.remote, to: scenario.local, base: scenario.base)
            copies += result.conflictCopies.count
            repaired += result.repairedItemIDs.count

            let ids = result.board.items.map(\.id)
            #expect(ids.count == Set(ids).count, "rodada \(round): ids repetidos")
            let byID = Dictionary(result.board.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            #expect(result.board.items.allSatisfy { Board.hasValidParentChain($0, in: byID) }, "rodada \(round): cadeia de pais inválida")
            #expect(result.board.formatVersion == result.board.requiredFormatVersion, "rodada \(round): versão do formato")
            #expect(result.conflictCopies.keys.allSatisfy { byID[$0] != nil }, "rodada \(round): cópia que não está no mural")
            #expect(result.conflictCopies.allSatisfy { $0.key != $0.value }, "rodada \(round): cópia igual ao original")
            #expect(Set(result.repairedItemIDs).isSubset(of: Set(ids)), "rodada \(round): cartão consertado que não está no mural")

            // Ninguém perde o que escreveu: o texto editado aqui, e o editado lá (a não ser num cartão que lá mesmo foi apagado),
            // está em algum cartão do resultado, no cartão ou numa cópia de conflito.
            let texts = Set(result.board.items.compactMap(\.text))
            for item in scenario.local.items where item.text?.hasPrefix("daqui") == true {
                #expect(texts.contains(item.text ?? ""), "rodada \(round): perdeu o texto escrito aqui")
            }
            for item in scenario.remote.savedItems where !scenario.remote.deletedItemIDs.contains(item.id) {
                guard item.text?.hasPrefix("de lá") == true else { continue }
                #expect(texts.contains(item.text ?? ""), "rodada \(round): perdeu o texto escrito lá")
            }
        }
        // Os sorteios passam de verdade pelas cópias de conflito e pelo conserto da estrutura.
        #expect(copies > 0 && repaired > 0)
    }

    // MARK: Textos livres

    @Test("Texto livre novo de outra pessoa entra")
    func newFreeTextEnters() {
        let existing = freeText(1, "daqui")
        let local = board([], freeTexts: [existing])
        let result = apply(RemoteBoardChanges(savedFreeTexts: [freeText(2, "chegou")]), to: local, base: local)
        #expect(result.board.freeTexts == [existing, freeText(2, "chegou")])
    }

    @Test("Texto livre apagado aqui, que a base tem, continua apagado")
    func deletedFreeTextStaysDeleted() {
        let base = board([], freeTexts: [freeText(1, "antes")])
        let result = apply(
            RemoteBoardChanges(savedFreeTexts: [freeText(1, "antes e depois")]), to: board([]), base: base)
        #expect(result.board.freeTexts.isEmpty)
    }

    @Test("Texto livre igual à base, ou que a base não tem, vale o que chegou")
    func unchangedFreeTextTakesTheRemote() {
        let original = freeText(1, "antes")
        let base = board([], freeTexts: [original, freeText(3, "mantido")])
        let local = board([], freeTexts: [original, freeText(3, "mantido"), freeText(2, "criado aqui")])
        let remote = RemoteBoardChanges(savedFreeTexts: [
            freeText(1, "depois", at: BoardPoint(x: 70, y: 70)), freeText(2, "criado lá também"),
        ])

        let result = apply(remote, to: local, base: base)
        #expect(result.board.freeTexts.map(\.text) == ["depois", "mantido", "criado lá também"])
        #expect(result.board.freeTexts[0].position == BoardPoint(x: 70, y: 70))
    }

    @Test("Texto livre mudado aqui desde a base fica como está")
    func changedFreeTextStaysLocal() {
        let base = board([], freeTexts: [freeText(1, "antes")])
        let local = board([], freeTexts: [freeText(1, "mudado aqui")])
        let result = apply(RemoteBoardChanges(savedFreeTexts: [freeText(1, "mudado lá")]), to: local, base: base)
        #expect(result.board.freeTexts.map(\.text) == ["mudado aqui"])
    }

    @Test("Texto livre apagado por outra pessoa sai, mesmo mudado aqui")
    func remoteDeletedFreeTextLeaves() {
        let base = board([], freeTexts: [freeText(1, "antes"), freeText(2, "outro")])
        let local = board([], freeTexts: [freeText(1, "mudado aqui"), freeText(2, "outro")])
        let result = apply(RemoteBoardChanges(deletedFreeTextIDs: [id(1)]), to: local, base: base)
        #expect(result.board.freeTexts.map(\.text) == ["outro"])
    }
}
