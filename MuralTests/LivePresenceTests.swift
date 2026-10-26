import CoreGraphics
import Foundation
import GroupActivities
import MuralKit
import MuralSync
import Testing

@testable import Mural

/// A presença no Live Share: quem pode entrar, quem aparece e o que cada mensagem muda. Tudo puro, sem sessão do SharePlay.
@Suite("Live Share: presença das pessoas")
struct LivePresenceTests {
    private let board = BoardID()
    private let otherBoard = BoardID()
    private let zone = CloudZoneID(name: "Mural-teste", ownerName: "dono")

    // MARK: Atalhos

    private func guest(_ userRecordName: String?, name: String? = nil, accepted: Bool = true) -> ShareSummary.Participant {
        ShareSummary.Participant(displayName: name, userRecordName: userRecordName, permission: .readWrite, isAccepted: accepted)
    }

    /// O convite como o Mac de um convidado o vê: o dono "dono" (Ana) e a convidada "bia" (Bia), salvo o que o teste mudar.
    private func share(
        owner: String? = "dono", ownerName: String? = "Ana", guests: [ShareSummary.Participant]? = nil
    ) -> ShareSummary {
        ShareSummary(
            zone: zone, ownerDisplayName: ownerName, ownerUserRecordName: owner, participants: guests ?? [guest("bia", name: "Bia")])
    }

    /// A presença deste mural no Mac da pessoa "eu", com o convite padrão.
    private func newPresence() -> LivePresence {
        LivePresence(boardID: board, roster: LiveRoster(share: share(), localUserRecordName: "eu"))
    }

    private func hello(
        _ userRecordName: String?, name: String? = nil, focus: LiveFocus? = nil, reply: Bool = false, in boardID: BoardID? = nil
    ) -> LiveEvent {
        .hello(
            LiveHello(
                boardID: boardID ?? board, userRecordName: userRecordName, displayName: name, focus: focus, replyRequested: reply))
    }

    private func focus(editing: Bool = false) -> LiveFocus {
        LiveFocus(itemID: UUID(), isEditing: editing)
    }

    private func drag(x: Double = 10, y: Double = 20) -> LiveDrag {
        LiveDrag(kind: .item, id: UUID(), x: x, y: y)
    }

    /// Uma pessoa que entra com o `userRecordName` dado; devolve o id dela na sessão.
    private func join(_ userRecordName: String, into presence: inout LivePresence) -> UUID {
        let id = UUID()
        presence.receive(hello(userRecordName), from: id)
        return id
    }

    private func roundTrip<Value: Codable>(_ value: Value) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
    }

    // MARK: Quem pode entrar

    @Test("O dono, visto do Mac de um convidado, entra com o nome do convite; a própria pessoa entra sem nome")
    func ownerAndLocalPersonEnter() {
        let roster = LiveRoster(share: share(), localUserRecordName: "eu")

        #expect(roster.allows("dono"))
        #expect(roster.name(of: "dono") == "Ana")
        #expect(roster.allows("bia"))
        #expect(roster.name(of: "bia") == "Bia")
        #expect(roster.allows("eu"))
        #expect(roster.name(of: "eu") == nil, "é ela em outro Mac: o convite não a nomeia")
        #expect(!roster.allows("intruso"))
        #expect(!roster.allows(nil))
    }

    @Test("O marcador de dono padrão, que o CloudKit põe no Mac do dono, não identifica ninguém")
    func defaultOwnerMarkerNeverEnters() {
        let marker = CloudZoneID.defaultOwnerName
        let invite = share(owner: marker, guests: [guest(marker, name: "Fantasma"), guest("bia", name: "Bia")])

        let roster = LiveRoster(share: invite, localUserRecordName: "ana-real")

        #expect(marker == "__defaultOwner__")
        #expect(!roster.allows(marker))
        #expect(roster.name(of: marker) == nil)
        #expect(roster.allows("ana-real"), "o dono entra pelo próprio nome, que o Mac dele sabe")
        #expect(roster.allows("bia"))
        #expect(!LiveRoster(share: nil, localUserRecordName: marker).allows(marker))
    }

    @Test("Convidado com convite pendente, ou sem nome de registro, não entra")
    func pendingOrUnidentifiedGuestsDoNotEnter() {
        let pending = guest("dani", name: "Dani", accepted: false)
        let invite = share(guests: [pending, guest(nil, name: "Sem registro"), guest("bia", name: "Bia")])

        let roster = LiveRoster(share: invite, localUserRecordName: "eu")

        #expect(!roster.allows("dani"))
        #expect(roster.name(of: "dani") == nil)
        #expect(roster.allows("bia"))
        #expect(roster.name(of: "bia") == "Bia")
    }

    @Test("A própria pessoa, quando também está no convite, fica com o nome do convite")
    func localPersonKeepsTheNameFromTheShare() {
        let roster = LiveRoster(share: share(guests: [guest("eu", name: "Eu mesma")]), localUserRecordName: "eu")

        #expect(roster.allows("eu"))
        #expect(roster.name(of: "eu") == "Eu mesma")
    }

    @Test("Sem convite, só a própria pessoa entra; sem ela, ninguém")
    func withoutShareOnlyTheLocalPersonEnters() {
        let alone = LiveRoster(share: nil, localUserRecordName: "eu")
        #expect(alone.allows("eu"))
        #expect(!alone.allows("dono"))
        #expect(!alone.allows(nil))

        let nobody = LiveRoster(share: nil, localUserRecordName: nil)
        #expect(!nobody.allows("eu"))
        #expect(!nobody.allows(nil))
    }

    // MARK: hello

    @Test("hello de quem está no convite: a pessoa aparece conferida, com o nome do convite, a cor e o cartão aberto")
    func verifiedHelloAddsTheVerifiedPerson() throws {
        var presence = newPresence()
        let id = UUID()
        let open = focus(editing: true)

        let reaction = presence.receive(hello("dono", name: "Mac da Ana", focus: open), from: id)

        #expect(reaction == LiveReaction())
        let peer = try #require(presence.peers[id])
        #expect(peer.id == id)
        #expect(peer.name == "Ana", "o nome do convite vale mais que o do Mac")
        #expect(peer.userRecordName == "dono")
        #expect(peer.isVerified)
        #expect(peer.colorIndex == LivePresence.colorIndex(for: id))
        #expect(peer.focus == open)
        #expect(peer.pointer == nil && peer.drag == nil)
        #expect(presence.verifiedIDs == [id])
        #expect(presence.visiblePeers.map(\.id) == [id])
        #expect(presence.unverifiedCount == 0)
    }

    @Test("A própria pessoa em outro Mac é conferida, com o nome que o outro Mac deu")
    func theSamePersonOnAnotherMacIsVerified() throws {
        var presence = newPresence()
        let id = UUID()

        presence.receive(hello("eu", name: "MacBook da Bia"), from: id)

        let peer = try #require(presence.peers[id])
        #expect(peer.isVerified)
        #expect(peer.name == "MacBook da Bia", "o convite não nomeia a própria pessoa")
    }

    @Test("hello de quem não está no convite: entra sem conferência e pede reler o convite só na primeira vez de cada pessoa")
    func unverifiedHelloAsksForARefreshOnlyOnce() throws {
        var presence = newPresence()
        let stranger = UUID()

        let first = presence.receive(hello("estranho", name: "Mac do Zé"), from: stranger)

        #expect(first == LiveReaction(needsRosterRefresh: true))
        let peer = try #require(presence.peers[stranger])
        #expect(!peer.isVerified)
        #expect(peer.name == "Mac do Zé")
        #expect(presence.verifiedIDs.isEmpty)
        #expect(presence.visiblePeers.isEmpty)
        #expect(presence.unverifiedCount == 1)

        #expect(presence.receive(hello("estranho", name: "Mac do Zé"), from: stranger) == LiveReaction(), "já pediu para esta pessoa")
        #expect(presence.receive(hello(nil), from: UUID()).needsRosterRefresh, "outra pessoa de fora pede de novo")
        #expect(presence.unverifiedCount == 2)
    }

    @Test("O nome vem do convite, depois do Mac da pessoa, e por fim é Convidado")
    func nameFallsBackStepByStep() {
        var presence = newPresence()
        let fromShare = UUID()
        let fromMac = UUID()
        let anonymous = UUID()
        let emptyName = UUID()

        presence.receive(hello("dono", name: "Mac"), from: fromShare)
        presence.receive(hello("estranho", name: "Mac do Zé"), from: fromMac)
        presence.receive(hello("outro"), from: anonymous)
        presence.receive(hello(nil, name: ""), from: emptyName)

        #expect(presence.peers[fromShare]?.name == "Ana")
        #expect(presence.peers[fromMac]?.name == "Mac do Zé")
        #expect(presence.peers[anonymous]?.name == "Convidado")
        #expect(presence.peers[emptyName]?.name == "Convidado", "nome vazio vale como sem nome")
    }

    @Test("Um segundo hello da mesma pessoa atualiza o cartão aberto e mantém o ponteiro e o arrasto")
    func aSecondHelloUpdatesTheSamePerson() throws {
        var presence = newPresence()
        let id = join("bia", into: &presence)
        let moving = drag()
        presence.receive(.pointer(boardID: board, x: 5, y: 6), from: id)
        presence.receive(.drag(boardID: board, drag: moving), from: id)
        let open = focus(editing: true)

        presence.receive(hello("bia", focus: open), from: id)

        #expect(presence.peers.count == 1)
        let peer = try #require(presence.peers[id])
        #expect(peer.focus == open)
        #expect(peer.pointer == CGPoint(x: 5, y: 6))
        #expect(peer.drag == moving)
    }

    @Test("hello que passa a dizer um nome de registro de fora tira a conferência e o que a pessoa mostrava")
    func helloWithAnotherRecordNameRemovesTheVerification() throws {
        var presence = newPresence()
        let id = join("bia", into: &presence)
        presence.receive(.pointer(boardID: board, x: 5, y: 6), from: id)
        presence.receive(.drag(boardID: board, drag: drag()), from: id)

        let reaction = presence.receive(hello("estranho"), from: id)

        #expect(reaction == LiveReaction(needsRosterRefresh: true))
        let peer = try #require(presence.peers[id])
        #expect(!peer.isVerified)
        #expect(peer.pointer == nil && peer.drag == nil)
    }

    @Test("hello que pede resposta: a resposta vai só a quem pediu, também quando a pessoa não foi conferida")
    func replyRequestedAnswersTheAskerOnly() {
        var presence = newPresence()
        let known = UUID()
        let stranger = UUID()
        let quiet = UUID()

        #expect(presence.receive(hello("bia", reply: true), from: known) == LiveReaction(replyHelloTo: known))
        #expect(
            presence.receive(hello("estranho", reply: true), from: stranger)
                == LiveReaction(replyHelloTo: stranger, needsRosterRefresh: true))
        #expect(presence.receive(hello("dono", reply: false), from: quiet).replyHelloTo == nil)
    }

    // MARK: Outro mural e quem não foi conferido

    @Test("Mensagem de outro mural não muda nada")
    func messagesFromAnotherBoardChangeNothing() {
        var presence = newPresence()
        let id = join("bia", into: &presence)
        presence.receive(.pointer(boardID: board, x: 1, y: 2), from: id)
        presence.receive(.drag(boardID: board, drag: drag()), from: id)
        presence.receive(.focus(boardID: board, focus: focus()), from: id)
        let before = presence

        let events: [LiveEvent] = [
            hello("bia", name: "Outra", focus: focus(), reply: true, in: otherBoard),
            .saved(boardID: otherBoard),
            .focus(boardID: otherBoard, focus: nil),
            .dragEnded(boardID: otherBoard),
            .pointerLeft(boardID: otherBoard),
        ]
        for event in events {
            #expect(presence.receive(event, from: id) == LiveReaction(), "\(event)")
        }
        #expect(presence.receive(hello("estranho", reply: true, in: otherBoard), from: UUID()) == LiveReaction())
        presence.receive(.pointer(boardID: otherBoard, x: 99, y: 99), from: id)
        presence.receive(.drag(boardID: otherBoard, drag: drag(x: 99, y: 99)), from: id)

        #expect(presence == before)
    }

    @Test("Movimento, cartão e aviso de envio de quem não foi conferido são ignorados, e quem nunca disse hello não vira pessoa")
    func unverifiedPeopleAreIgnored() throws {
        var presence = newPresence()
        let stranger = UUID()
        presence.receive(hello("estranho"), from: stranger)
        let unknown = UUID()

        for id in [stranger, unknown] {
            presence.receive(.pointer(boardID: board, x: 5, y: 6), from: id)
            presence.receive(.drag(boardID: board, drag: drag()), from: id)
            let reactions = [
                presence.receive(.saved(boardID: board), from: id),
                presence.receive(.focus(boardID: board, focus: focus()), from: id),
                presence.receive(.dragEnded(boardID: board), from: id),
                presence.receive(.pointerLeft(boardID: board), from: id),
            ]
            #expect(reactions.allSatisfy { $0 == LiveReaction() })
        }

        let peer = try #require(presence.peers[stranger])
        #expect(peer.pointer == nil && peer.drag == nil && peer.focus == nil)
        #expect(presence.peers[unknown] == nil)
        #expect(presence.peers.count == 1)
    }

    // MARK: Movimento e cartão

    @Test("O cartão aberto vem no focus e some com focus nil")
    func focusEventsSetAndClearTheOpenCard() {
        var presence = newPresence()
        let id = join("bia", into: &presence)
        let open = focus(editing: false)

        presence.receive(.focus(boardID: board, focus: open), from: id)
        #expect(presence.peers[id]?.focus == open)

        presence.receive(.focus(boardID: board, focus: nil), from: id)
        #expect(presence.peers[id]?.focus == nil)
    }

    @Test("dragEnded limpa o arrasto e pointerLeft limpa o ponteiro, cada um sem mexer no outro")
    func dragEndedAndPointerLeftClearTheirOwnState() {
        var presence = newPresence()
        let id = join("bia", into: &presence)
        let moving = drag()
        presence.receive(.pointer(boardID: board, x: 3, y: 4), from: id)
        presence.receive(.drag(boardID: board, drag: moving), from: id)
        #expect(presence.peers[id]?.pointer == CGPoint(x: 3, y: 4))
        #expect(presence.peers[id]?.drag == moving)

        presence.receive(.dragEnded(boardID: board), from: id)
        #expect(presence.peers[id]?.drag == nil)
        #expect(presence.peers[id]?.pointer == CGPoint(x: 3, y: 4), "o fim do arrasto não tira o ponteiro")

        presence.receive(.drag(boardID: board, drag: moving), from: id)
        presence.receive(.pointerLeft(boardID: board), from: id)
        #expect(presence.peers[id]?.pointer == nil)
        #expect(presence.peers[id]?.drag == moving, "o ponteiro sair do mural não tira o arrasto")
    }

    @Test("O ponteiro limpa o arrasto da pessoa e o arrasto não mexe no ponteiro: um movimento atrasado não deixa o arrasto preso")
    func pointerClearsTheDragButTheDragKeepsThePointer() {
        var presence = newPresence()
        let id = join("bia", into: &presence)
        let moving = drag()

        presence.receive(.pointer(boardID: board, x: 1, y: 2), from: id)
        presence.receive(.drag(boardID: board, drag: moving), from: id)
        #expect(presence.peers[id]?.pointer == CGPoint(x: 1, y: 2), "o arrasto não mexe no ponteiro")
        #expect(presence.peers[id]?.drag == moving)

        // O fim do arrasto chega pelo canal confiável e, depois, um movimento atrasado do outro canal o traz de volta.
        presence.receive(.dragEnded(boardID: board), from: id)
        presence.receive(.drag(boardID: board, drag: moving), from: id)
        #expect(presence.peers[id]?.drag == moving, "o arrasto fantasma fica até a próxima mensagem de ponteiro")

        presence.receive(.pointer(boardID: board, x: 7, y: 8), from: id)
        #expect(presence.peers[id]?.drag == nil, "quem manda ponteiro não está arrastando")
        #expect(presence.peers[id]?.pointer == CGPoint(x: 7, y: 8))
    }

    @Test("saved de pessoa conferida pede a busca; de quem não foi conferido, não")
    func savedFromAVerifiedPersonRequestsAFetch() {
        var presence = newPresence()
        let known = join("bia", into: &presence)
        let stranger = UUID()
        presence.receive(hello("estranho"), from: stranger)

        #expect(presence.receive(.saved(boardID: board), from: known) == LiveReaction(fetchRequested: true))
        #expect(presence.receive(.saved(boardID: board), from: stranger) == LiveReaction())
    }

    // MARK: Saída

    @Test("bye tira a pessoa, conferida ou não, e quem volta de fora faz o convite ser relido de novo")
    func byeRemovesThePerson() {
        var presence = newPresence()
        let known = join("bia", into: &presence)
        let stranger = UUID()
        presence.receive(hello("estranho"), from: stranger)
        #expect(presence.peers.count == 2)

        #expect(presence.receive(.bye, from: known) == LiveReaction())
        presence.receive(.bye, from: stranger)
        presence.receive(.bye, from: UUID())

        #expect(presence.peers.isEmpty)
        #expect(presence.verifiedIDs.isEmpty)
        #expect(presence.unverifiedCount == 0)
        #expect(presence.receive(hello("estranho"), from: stranger).needsRosterRefresh, "é outra visita")
    }

    @Test("Pela lista de participantes sai quem estava nela e não está mais; quem só mandou mensagem fica até aparecer numa lista")
    func participantsListRemovesOnlyThoseWhoWereListed() {
        var presence = newPresence()
        let ana = UUID()
        let bia = UUID()
        let early = UUID()
        presence.receive(hello("dono"), from: ana)
        presence.receive(hello("bia"), from: bia)
        presence.receive(hello("estranho"), from: early)

        #expect(presence.setParticipants([ana, bia]) == [ana, bia], "quem chegou")
        #expect(presence.peers.count == 3, "early mandou mensagem antes de aparecer numa lista, e a lista pode chegar depois")

        #expect(presence.setParticipants([bia]).isEmpty)
        #expect(presence.peers[ana] == nil, "estava na lista e saiu")
        #expect(presence.peers[bia] != nil)
        #expect(presence.peers[early] != nil, "nunca apareceu numa lista: fica")

        #expect(presence.setParticipants([bia, early]) == [early])
        #expect(presence.peers[early] != nil)

        #expect(presence.setParticipants([bia]).isEmpty)
        #expect(presence.peers[early] == nil, "agora a lista a conhecia, e ela saiu")
        #expect(presence.verifiedIDs == [bia])
        #expect(presence.unverifiedCount == 0)
    }

    // MARK: Mudança do convite

    @Test("O convite foi relido: quem estava de fora passa a ser conferido, com o nome do convite e o cartão que mostrou ao entrar")
    func refreshedRosterVerifiesTheLateGuest() throws {
        var presence = newPresence()
        let dani = UUID()
        let open = focus(editing: true)
        presence.receive(hello("dani", name: "Mac da Dani", focus: open), from: dani)
        #expect(presence.unverifiedCount == 1)
        #expect(presence.peers[dani]?.name == "Mac da Dani")

        let invite = share(guests: [guest("bia", name: "Bia"), guest("dani", name: "Dani")])
        let refreshed = LiveRoster(share: invite, localUserRecordName: "eu")
        presence.setRoster(refreshed)

        let peer = try #require(presence.peers[dani])
        #expect(peer.isVerified)
        #expect(peer.name == "Dani", "agora o convite a nomeia")
        #expect(peer.focus == open)
        #expect(presence.verifiedIDs == [dani])
        #expect(presence.unverifiedCount == 0)
        #expect(presence.roster == refreshed)
    }

    @Test("O convite perdeu a pessoa: ela deixa de ser conferida e perde ponteiro, arrasto e cartão; o nome volta ao do Mac dela")
    func rosterWithoutThePersonRemovesTheVerification() throws {
        var presence = newPresence()
        let id = UUID()
        presence.receive(hello("bia", name: "Mac da Bia", focus: focus()), from: id)
        presence.receive(.pointer(boardID: board, x: 1, y: 2), from: id)
        presence.receive(.drag(boardID: board, drag: drag()), from: id)
        #expect(presence.peers[id]?.name == "Bia")

        presence.setRoster(LiveRoster(share: share(guests: []), localUserRecordName: "eu"))

        let peer = try #require(presence.peers[id])
        #expect(!peer.isVerified)
        #expect(peer.name == "Mac da Bia")
        #expect(peer.pointer == nil && peer.drag == nil && peer.focus == nil)
        #expect(presence.visiblePeers.isEmpty)
        #expect(presence.unverifiedCount == 1)

        presence.receive(.pointer(boardID: board, x: 9, y: 9), from: id)
        #expect(presence.peers[id]?.pointer == nil, "sem conferência, o movimento é ignorado")
    }

    // MARK: Ordem e cor

    @Test("As pessoas conferidas saem pelo nome, sem distinguir maiúsculas, e pelo id no empate")
    func visiblePeersAreSortedByNameThenByID() {
        let invite = share(owner: "caio", ownerName: "Caio", guests: [guest("bia", name: "bia"), guest("ana", name: "Ana")])
        var presence = LivePresence(boardID: board, roster: LiveRoster(share: invite, localUserRecordName: "eu"))
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let caio = UUID()
        let bia = UUID()

        presence.receive(hello("caio"), from: caio)
        presence.receive(hello("bia"), from: bia)
        presence.receive(hello("ana"), from: second)
        presence.receive(hello("ana"), from: first)
        presence.receive(hello("estranho"), from: UUID())

        #expect(presence.visiblePeers.map(\.name) == ["Ana", "Ana", "bia", "Caio"])
        #expect(presence.visiblePeers.map(\.id) == [first, second, bia, caio])
        #expect(presence.verifiedIDs == [first, second, bia, caio])
        #expect(presence.unverifiedCount == 1)
    }

    @Test("A cor sai do primeiro byte do id da pessoa, igual em todos os Macs")
    func colorComesFromTheFirstByteOfTheID() {
        func id(firstByte: String) -> UUID { UUID(uuidString: "\(firstByte)000000-0000-0000-0000-000000000000")! }

        #expect(LivePresence.paletteCount == 8)
        #expect(LivePresence.colorIndex(for: id(firstByte: "00")) == 0)
        #expect(LivePresence.colorIndex(for: id(firstByte: "0B")) == 3)
        #expect(LivePresence.colorIndex(for: id(firstByte: "FF")) == 7)
        let some = UUID()
        #expect(LivePresence.colorIndex(for: some) == LivePresence.colorIndex(for: some))
        #expect((0..<64).allSatisfy { _ in (0..<LivePresence.paletteCount).contains(LivePresence.colorIndex(for: UUID())) })
    }

    // MARK: Mensagens e atividade

    @Test("Eventos, movimentos e a atividade do SharePlay vão em JSON e voltam iguais")
    func messagesSurviveJSON() throws {
        let item = UUID()
        let events: [LiveEvent] = [
            hello("bia", name: "Bia", focus: LiveFocus(itemID: item, isEditing: true), reply: true),
            hello(nil),
            .saved(boardID: board),
            .focus(boardID: board, focus: LiveFocus(itemID: item, isEditing: false)),
            .focus(boardID: board, focus: nil),
            .dragEnded(boardID: board),
            .pointerLeft(boardID: board),
            .bye,
        ]
        let motions: [LiveMotion] = [
            .pointer(boardID: board, x: 12.5, y: -3),
            .drag(boardID: board, drag: LiveDrag(kind: .freeText, id: item, x: 40, y: 80)),
            .drag(boardID: board, drag: LiveDrag(kind: .item, id: item, x: 0, y: 0)),
        ]
        let activities = [
            MuralLiveActivity(boardID: board, shareURL: URL(string: "https://www.icloud.com/share/0abc")),
            MuralLiveActivity(boardID: board, shareURL: nil),
        ]

        for event in events { #expect(try roundTrip(event) == event, "\(event)") }
        for motion in motions { #expect(try roundTrip(motion) == motion, "\(motion)") }
        for activity in activities { #expect(try roundTrip(activity) == activity, "\(activity)") }
        if case .hello(let sent) = events[1] { #expect(sent.version == LiveHello.currentVersion) }
    }

    @Test("A atividade do SharePlay tem identificador próprio e título neutro, sem o nome do mural, imagem nem endereço de reserva")
    func activityMetadataIsNeutral() {
        let activity = MuralLiveActivity(boardID: board, shareURL: nil)

        #expect(MuralLiveActivity.activityIdentifier == "com.joaocosta.Mural.live-share")
        #expect(activity.metadata.title == "Mural ao vivo")
        #expect(activity.metadata.type == .createTogether)
        #expect(activity.metadata.fallbackURL == nil)
        #expect(activity.metadata.previewImage == nil)
    }
}
