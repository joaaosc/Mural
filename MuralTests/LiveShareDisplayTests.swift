import Foundation
import MuralKit
import Testing

@testable import Mural

/// A seção do Live Share no popover de Compartilhar: o que ela mostra a partir da fase do controlador e dos fatos do mural.
@MainActor
@Suite("Live Share: seção do popover")
struct LiveShareDisplayTests {
    private let board = BoardID()
    private let otherBoard = BoardID()

    // MARK: Atalhos

    private func peer(_ name: String, color: Int = 0, focus: LiveFocus? = nil) -> LivePeer {
        LivePeer(
            id: UUID(), name: name, userRecordName: name.lowercased(), isVerified: true, colorIndex: color, pointer: nil, drag: nil,
            focus: focus)
    }

    /// O popover de um mural compartilhado, com conta, sem chamada e sem Live Share, salvo o que o teste mudar.
    private func make(
        phase: LiveShareController.Phase = .idle, peers: [LivePeer] = [], unverified: Int = 0, shared: Bool = true,
        account: Bool = true, inCall: Bool = false, titles: [UUID: String] = [:]
    ) -> LiveShareDisplay? {
        LiveShareDisplay.make(
            phase: phase, boardID: board, peers: peers, unverifiedCount: unverified, isShared: shared, accountAvailable: account,
            isInCall: inCall, itemTitle: { titles[$0] })
    }

    // MARK: Antes de começar

    @Test func withoutAccountTheSectionIsHidden() {
        #expect(make(account: false) == nil)
        #expect(make(shared: false, account: false) == nil)
    }

    @Test func unsharedBoardExplainsWhyItCannotStart() {
        #expect(make(shared: false)?.state == .unavailable("Convide pessoas para usar o Live Share."))
    }

    @Test func sharedBoardIsReadyWithoutACall() {
        #expect(make()?.state == .ready(inCall: false))
    }

    @Test func sharedBoardIsReadyDuringACall() {
        #expect(make(inCall: true)?.state == .ready(inCall: true))
    }

    // MARK: Entrando e ao vivo

    @Test func connectingHereShowsTheProgress() {
        #expect(make(phase: .connecting(board))?.state == .connecting)
    }

    @Test func liveHereWithoutPeersWaitsForThem() {
        #expect(make(phase: .live(board))?.state == .live(people: [], unverifiedCount: 0))
    }

    @Test func liveHereListsEachPersonWithWhatTheyDo() {
        let notes = UUID()
        let list = UUID()
        let bia = peer("Bia", color: 1, focus: LiveFocus(itemID: notes, isEditing: true))
        let caio = peer("Caio", color: 4, focus: LiveFocus(itemID: list, isEditing: false))
        let dani = peer("Dani", color: 7)
        let display = make(
            phase: .live(board), peers: [bia, caio, dani], titles: [notes: "Roteiro de sábado", list: "Lista de compras"])
        #expect(
            display?.state
                == .live(
                    people: [
                        .init(id: bia.id, name: "Bia", colorIndex: 1, activity: "editando “Roteiro de sábado”"),
                        .init(id: caio.id, name: "Caio", colorIndex: 4, activity: "vendo “Lista de compras”"),
                        .init(id: dani.id, name: "Dani", colorIndex: 7, activity: "no mural"),
                    ], unverifiedCount: 0))
    }

    @Test func anUnknownOrEmptyTitleSaysACard() {
        let missing = UUID()
        let untitled = UUID()
        let bia = peer("Bia", focus: LiveFocus(itemID: missing, isEditing: true))
        let caio = peer("Caio", focus: LiveFocus(itemID: untitled, isEditing: false))
        guard case .live(let people, _)? = make(phase: .live(board), peers: [bia, caio], titles: [untitled: "  "])?.state else {
            Issue.record("o mural devia estar ao vivo")
            return
        }
        #expect(people.map(\.activity) == ["editando um cartão", "vendo um cartão"])
    }

    @Test func peopleWithoutAccessAreCountedNotListed() {
        let display = make(phase: .live(board), peers: [peer("Bia")], unverified: 2)
        guard case .live(let people, let unverifiedCount)? = display?.state else {
            Issue.record("o mural devia estar ao vivo")
            return
        }
        #expect(people.map(\.name) == ["Bia"])
        #expect(unverifiedCount == 2)
    }

    @Test func aLiveSessionKeepsItsSectionEvenIfTheAccountGoesAway() {
        // Quem está ao vivo precisa poder sair, mesmo que a conta tenha caído no meio da sessão.
        #expect(make(phase: .live(board), account: false)?.state == .live(people: [], unverifiedCount: 0))
        #expect(make(phase: .connecting(board), account: false)?.state == .connecting)
    }

    // MARK: Outro mural ao vivo

    @Test func anotherBoardLiveDoesNotCountAsLiveHere() {
        #expect(make(phase: .live(otherBoard), peers: [peer("Bia")])?.state == .ready(inCall: false))
        #expect(make(phase: .connecting(otherBoard), inCall: true)?.state == .ready(inCall: true))
        #expect(make(phase: .live(otherBoard), shared: false)?.state == .unavailable("Convide pessoas para usar o Live Share."))
        #expect(make(phase: .live(otherBoard), account: false) == nil)
    }

    // MARK: Cores

    @Test func paletteHasOneColorPerPlaceAndWrapsAround() {
        #expect(LivePalette.colors.count == LivePresence.paletteCount)
        #expect(LivePalette.color(0) == LivePalette.colors[0])
        #expect(LivePalette.color(LivePresence.paletteCount) == LivePalette.color(0))
        #expect(LivePalette.color(LivePresence.paletteCount + 3) == LivePalette.color(3))
        #expect(LivePalette.color(-1) == LivePalette.colors[LivePresence.paletteCount - 1])
    }
}
