import Foundation
import Testing

@testable import MuralKit

@Suite("Mover cartões e guardá-los em pastas")
struct BoardMoveTests {
    // Ordem da lista: `folder` primeiro e `child` no meio, para provar que mover leva ao fim.
    let folder = BoardItem(kind: .folder, title: "Pasta", position: BoardPoint(x: 100, y: 100))
    let child: BoardItem
    let otherFolder = BoardItem(kind: .folder, title: "Outra pasta", position: BoardPoint(x: 400, y: 100))
    let note = BoardItem(kind: .text, title: "Nota", position: BoardPoint(x: 100, y: 400))
    let sticky = BoardItem(kind: .sticky, title: "Post-it", position: BoardPoint(x: 300, y: 400))
    let initial: Board

    init() {
        child = BoardItem(kind: .text, title: "Dentro da pasta", parentID: folder.id)
        initial = Board(items: [folder, child, otherFolder, note, sticky])
    }

    // MARK: Board.move

    @Test("Mover troca a posição e leva o cartão para o fim da lista")
    func moveChangesPositionAndGoesLast() {
        var board = initial
        let target = BoardPoint(x: 250, y: 330)
        let changed = board.move(id: folder.id, to: target)
        #expect(changed)
        var moved = folder
        moved.position = target
        #expect(board.items.last == moved)
        #expect(board.items.dropLast().map(\.id) == [child.id, otherFolder.id, note.id, sticky.id])
    }

    @Test("Mover o cartão que já está por cima só troca a posição")
    func moveTopCardKeepsOrder() {
        var board = initial
        let target = BoardPoint(x: 10, y: 20)
        let changed = board.move(id: sticky.id, to: target)
        #expect(changed)
        #expect(board.items.map(\.id) == initial.items.map(\.id))
        #expect(board.item(id: sticky.id)?.position == target)
    }

    @Test("Mover ignora cartão de dentro de pasta e id desconhecido")
    func moveIgnoresChildrenAndUnknownIDs() {
        var board = initial
        let movedChild = board.move(id: child.id, to: BoardPoint(x: 5, y: 5))
        let movedUnknown = board.move(id: UUID(), to: BoardPoint(x: 5, y: 5))
        #expect(!movedChild)
        #expect(!movedUnknown)
        #expect(board == initial)
    }

    // MARK: Board.moveIntoFolder

    @Test("Guardar em pasta tira o cartão do mural e o põe na pasta, sem mexer na posição nem na ordem")
    func moveIntoFolderSucceeds() {
        var board = initial
        let changed = board.moveIntoFolder(id: note.id, folderID: otherFolder.id)
        #expect(changed)
        #expect(!board.rootItems.contains { $0.id == note.id })
        #expect(board.children(of: otherFolder.id).map(\.id) == [note.id])
        var stored = note
        stored.parentID = otherFolder.id
        #expect(board.item(id: note.id) == stored)
        #expect(board.items.map(\.id) == initial.items.map(\.id))
    }

    @Test("Guardar em pasta aceita pasta, cartão que já está numa pasta e destino dentro de pasta")
    func moveIntoFolderAcceptsNesting() throws {
        let nestedFolder = BoardItem(kind: .folder, title: "Pasta dentro de pasta", parentID: folder.id)
        let board = Board(items: initial.items + [nestedFolder])
        let cases: [(name: String, id: UUID, folderID: UUID)] = [
            ("pasta em pasta", otherFolder.id, folder.id),
            ("cartão que já está numa pasta", child.id, otherFolder.id),
            ("destino dentro de pasta", note.id, nestedFolder.id),
        ]
        for move in cases {
            var attempt = board
            let accepted = attempt.moveIntoFolder(id: move.id, folderID: move.folderID)
            #expect(accepted, "recusou \(move.name)")
            var expected = try #require(board.item(id: move.id))
            expected.parentID = move.folderID
            #expect(attempt.item(id: move.id) == expected, "mudou mais que o pai em \(move.name)")
            #expect(attempt.items.map(\.id) == board.items.map(\.id), "mudou a ordem da lista em \(move.name)")
        }
    }

    @Test("Guardar em pasta recusa o que não pode entrar, sem alterar o mural")
    func moveIntoFolderRefusals() {
        let cases: [(name: String, id: UUID, folderID: UUID)] = [
            ("destino que não é pasta", note.id, sticky.id),
            ("destino que já é o pai", child.id, folder.id),
            ("o próprio id", folder.id, folder.id),
            ("cartão desconhecido", UUID(), folder.id),
            ("pasta desconhecida", note.id, UUID()),
            ("os dois desconhecidos", UUID(), UUID()),
        ]
        for refusal in cases {
            var attempt = initial
            let accepted = attempt.moveIntoFolder(id: refusal.id, folderID: refusal.folderID)
            #expect(!accepted, "aceitou \(refusal.name)")
            #expect(attempt == initial, "alterou o mural em \(refusal.name)")
        }
    }

    // MARK: Board.moveToBoard

    @Test("Tirar da pasta solta o cartão na posição dada, no fim da lista")
    func moveToBoardSucceeds() {
        var board = initial
        let target = BoardPoint(x: 640, y: 220)
        let changed = board.moveToBoard(id: child.id, at: target)
        #expect(changed)
        var released = child
        released.parentID = nil
        released.position = target
        #expect(board.items.last == released)
        #expect(board.rootItems.contains { $0.id == child.id })
        #expect(board.children(of: folder.id).isEmpty)
        #expect(board.items.dropLast().map(\.id) == [folder.id, otherFolder.id, note.id, sticky.id])
    }

    @Test("Tirar da pasta recusa cartão que já está solto e id desconhecido")
    func moveToBoardRefusals() {
        var board = initial
        let movedNote = board.moveToBoard(id: note.id, at: BoardPoint(x: 5, y: 5))
        let movedFolder = board.moveToBoard(id: folder.id, at: BoardPoint(x: 5, y: 5))
        let movedUnknown = board.moveToBoard(id: UUID(), at: BoardPoint(x: 5, y: 5))
        #expect(!movedNote)
        #expect(!movedFolder)
        #expect(!movedUnknown)
        #expect(board == initial)
    }

    // MARK: BoardLayout.clamped

    @Test("Posição é arredondada e nunca fica abaixo da origem do mural")
    func clampedRoundsAndFloorsAtZero() {
        #expect(BoardLayout.clamped(BoardPoint(x: -40, y: -3)) == .zero)
        #expect(BoardLayout.clamped(BoardPoint(x: 10.4, y: 10.5)) == BoardPoint(x: 10, y: 11))
        #expect(BoardLayout.clamped(BoardPoint(x: -7.6, y: 25.6)) == BoardPoint(x: 0, y: 26))
        #expect(BoardLayout.clamped(BoardPoint(x: 0, y: 300)) == BoardPoint(x: 0, y: 300))
    }

    @Test("Posição com -0 ou valor inválido vira 0 positivo")
    func clampedNormalizesNegativeZeroAndNaN() {
        let almostZero = BoardLayout.clamped(BoardPoint(x: -0.4, y: .nan))
        #expect(almostZero == .zero)
        #expect(almostZero.x.sign == .plus)
        #expect(almostZero.y.sign == .plus)
    }

    // MARK: BoardLayout.folderID

    private var insideFolder: BoardPoint {
        let size = BoardLayout.cardSize(for: .folder)
        return BoardPoint(x: folder.position.x + size.width / 2, y: folder.position.y + size.height / 2)
    }

    @Test("Pasta sob o ponto: dentro devolve a pasta, fora devolve nil")
    func folderUnderPoint() {
        #expect(BoardLayout.folderID(at: insideFolder, among: initial.items) == folder.id)
        #expect(BoardLayout.folderID(at: BoardPoint(x: 400 + 10, y: 100 + 10), among: initial.items) == otherFolder.id)
        #expect(BoardLayout.folderID(at: BoardPoint(x: 300, y: 130), among: initial.items) == nil, "entre as duas pastas")
        #expect(BoardLayout.folderID(at: .zero, among: initial.items) == nil)
        #expect(BoardLayout.folderID(at: insideFolder, among: []) == nil)
    }

    @Test("Bordas esquerda e superior contam como dentro; direita e inferior, não")
    func folderEdges() {
        let size = BoardLayout.cardSize(for: .folder)
        let origin = folder.position
        let items = [folder]
        #expect(BoardLayout.folderID(at: origin, among: items) == folder.id)
        let lastInside = BoardPoint(x: origin.x + size.width - 0.5, y: origin.y + size.height - 0.5)
        #expect(BoardLayout.folderID(at: lastInside, among: items) == folder.id)
        #expect(BoardLayout.folderID(at: BoardPoint(x: origin.x + size.width, y: origin.y), among: items) == nil)
        #expect(BoardLayout.folderID(at: BoardPoint(x: origin.x, y: origin.y + size.height), among: items) == nil)
        #expect(BoardLayout.folderID(at: BoardPoint(x: origin.x - 0.5, y: origin.y), among: items) == nil)
        #expect(BoardLayout.folderID(at: BoardPoint(x: origin.x, y: origin.y - 0.5), among: items) == nil)
    }

    @Test("A pasta excluída é ignorada")
    func excludedFolderIsIgnored() {
        #expect(BoardLayout.folderID(at: insideFolder, among: [folder], excluding: folder.id) == nil)
        #expect(BoardLayout.folderID(at: insideFolder, among: [folder], excluding: otherFolder.id) == folder.id)
        #expect(BoardLayout.folderID(at: insideFolder, among: [folder], excluding: nil) == folder.id)
    }

    @Test("Cartões que não são pasta e pastas dentro de pasta não contam")
    func ignoresNonFoldersAndNestedFolders() {
        let cardOnTop = BoardItem(kind: .sticky, title: "Por cima", position: folder.position)
        let nestedFolder = BoardItem(kind: .folder, title: "Dentro de pasta", parentID: otherFolder.id, position: folder.position)
        #expect(BoardLayout.folderID(at: insideFolder, among: [folder, cardOnTop, nestedFolder]) == folder.id)
        #expect(BoardLayout.folderID(at: insideFolder, among: [cardOnTop, nestedFolder]) == nil)
    }

    @Test("Com pastas sobrepostas vale a de cima, a última da lista")
    func overlappingFoldersTopWins() {
        let below = BoardItem(kind: .folder, title: "Embaixo", position: BoardPoint(x: 100, y: 100))
        let above = BoardItem(kind: .folder, title: "Em cima", position: BoardPoint(x: 150, y: 140))
        let inBoth = BoardPoint(x: 180, y: 180)
        #expect(BoardLayout.folderID(at: inBoth, among: [below, above]) == above.id)
        #expect(BoardLayout.folderID(at: inBoth, among: [above, below]) == below.id)
        #expect(BoardLayout.folderID(at: inBoth, among: [below, above], excluding: above.id) == below.id)
        #expect(BoardLayout.folderID(at: BoardPoint(x: 110, y: 110), among: [below, above]) == below.id, "só a de baixo cobre o ponto")
    }
}
