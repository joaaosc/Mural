import AppKit
import CoreGraphics
import Foundation
import MuralKit
import MuralSync
import Testing

@testable import Mural

/// O controlador do Live Share com a sessão e o início falsos, sobre o ambiente de sincronização com o iCloud falso. A sessão do
/// SharePlay de verdade (`GroupSessionLink`) e o início pelo sistema (`SharePlayStarter`) precisam de uma chamada do FaceTime e não
/// têm teste automático; aqui se confere tudo o que o controlador decide com o que elas avisam.
@Suite("Live Share: controlador com sessão falsa", .serialized)
@MainActor
struct LiveShareControllerTests {
    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000.5)

    // MARK: Sessão

    @Test("Sessão de mural deste Mac: abre a aba, entra na sessão e a fase vira ao vivo")
    func acceptingASessionOfALocalBoardOpensTheTabAndJoins() async throws {
        let room = try await Self.makeRoom()
        defer { room.env.removeFiles() }
        let link = FakeLiveSessionLink(boardID: room.id)
        #expect(room.env.tabs.tab(for: room.id) == nil)

        await room.live.accept(link)

        #expect(room.live.phase == .live(room.id))
        #expect(room.live.isLive(room.id))
        #expect(!room.live.isLive(BoardID()))
        #expect(room.live.presence?.boardID == room.id)
        #expect(link.joined == 1)
        #expect(link.left == 0)
        #expect(room.env.tabs.tab(for: room.id) != nil, "a aba do mural foi aberta")
        #expect(room.env.controller.liveBoards.isEmpty, "ninguém foi conferido ainda")
        await room.env.finish()
    }

    @Test("Entrar na sessão: o hello vai a todos, pedindo resposta, com o usuário do iCloud deste Mac")
    func joiningSendsTheHelloToEveryone() async throws {
        let room = try await Self.makeRoom()
        defer { room.env.removeFiles() }
        let link = FakeLiveSessionLink(boardID: room.id)
        await room.live.accept(link)
        #expect(link.events.isEmpty, "nada sai antes de a sessão entrar")

        link.simulate(state: .joined)

        let hello = Self.hello(room.id, user: CloudSyncController.testUser, name: "Ana", reply: true)
        #expect(link.events == [.init(event: .hello(hello), recipients: .all)])
        await room.env.finish()
    }

    @Test("Participante novo recebe o hello daqui, só ele; os que já estavam não recebem de novo")
    func newParticipantGetsTheHelloAlone() async throws {
        let room = try await Self.makeRoom()
        defer { room.env.removeFiles() }
        let link = await Self.goLive(room)
        let first = UUID()
        let second = UUID()

        link.simulate(participants: [first])
        link.simulate(participants: [first, second])

        let hello = Self.hello(room.id, user: CloudSyncController.testUser, name: "Ana")
        #expect(link.events.map(\.recipients) == [.all, .only([first]), .only([second])])
        #expect(link.events.dropFirst().allSatisfy { $0.event == .hello(hello) }, "sem pedir resposta: quem chega já recebeu o pedido")
        await room.env.finish()
    }

    @Test("hello do convidado do convite: pessoa visível com o nome do convite, resposta quando pedida e mural em liveBoards")
    func verifiedGuestIsVisibleAndAnswered() async throws {
        let room = try await Self.makeRoom()
        defer { room.env.removeFiles() }
        let link = await Self.goLive(room)
        let guest = UUID()

        link.simulate(.hello(Self.hello(room.id, user: CloudSyncController.testGuest, name: "Bia", reply: true)), from: guest)

        let peers = room.live.peers(on: room.id)
        #expect(peers.map(\.id) == [guest])
        #expect(peers.first?.isVerified == true)
        #expect(peers.first?.name == CloudSyncController.testGuest, "vale o nome do convite")
        let reply = Self.hello(room.id, user: CloudSyncController.testUser, name: "Ana")
        #expect(link.events.last == .init(event: .hello(reply), recipients: .only([guest])), "a resposta vai só a quem pediu")
        #expect(room.env.controller.liveBoards == [room.id])
        #expect(room.live.peers(on: BoardID()).isEmpty, "outro mural não tem as pessoas deste")
        await room.env.finish()
    }

    @Test("hello de quem não está no convite: invisível, conta como não conferido, movimento ignorado e nada vai para ele")
    func strangerIsHiddenIgnoredAndGetsNothing() async throws {
        let room = try await Self.makeRoom()
        defer { room.env.removeFiles() }
        let link = await Self.goLive(room)
        let stranger = UUID()

        link.simulate(.hello(Self.hello(room.id, user: "desconhecido", name: "Intruso")), from: stranger)
        link.simulate(.pointer(boardID: room.id, x: 1, y: 2), from: stranger)
        link.simulate(.focus(boardID: room.id, focus: LiveFocus(itemID: UUID(), isEditing: true)), from: stranger)

        #expect(room.live.peers(on: room.id).isEmpty)
        #expect(room.live.presence?.unverifiedCount == 1)
        #expect(room.live.presence?.peers[stranger]?.pointer == nil, "o movimento dele foi ignorado")
        #expect(room.live.presence?.peers[stranger]?.focus == nil)
        #expect(room.env.controller.liveBoards.isEmpty)

        let sentBefore = link.events.count
        room.live.pointerMoved(to: CGPoint(x: 1, y: 1), in: room.id)
        room.live.dragChanged(LiveDrag(kind: .item, id: UUID(), x: 1, y: 1), in: room.id)
        room.live.focusChanged(LiveFocus(itemID: UUID(), isEditing: false), in: room.id)
        try await Task.sleep(for: .milliseconds(200))
        #expect(link.motions.isEmpty)
        #expect(link.events.count == sentBefore, "nada vai para quem não foi conferido")
        await room.env.finish()
    }

    @Test("Sessão nova substitui a antiga: a antiga recebe leave e despedida, e os avisos dela deixam de valer")
    func newSessionReplacesTheOldOne() async throws {
        let room = try await Self.makeRoom()
        defer { room.env.removeFiles() }
        let first = await Self.goLive(room)
        let guest = Self.verifyGuest(room, on: first)
        let second = FakeLiveSessionLink(boardID: room.id)

        await room.live.accept(second)

        #expect(first.left == 1)
        #expect(first.events.last == .init(event: .bye, recipients: .only([guest])))
        #expect(second.joined == 1)
        #expect(second.left == 0)
        #expect(room.live.phase == .live(room.id))
        #expect(room.live.peers(on: room.id).isEmpty, "a presença é nova")
        #expect(room.env.controller.liveBoards.isEmpty)

        first.simulate(.hello(Self.hello(room.id, user: CloudSyncController.testGuest, name: "Bia")), from: UUID())
        #expect(room.live.peers(on: room.id).isEmpty, "um aviso da sessão antiga é ignorado")
        await room.env.finish()
    }

    @Test("Mural que não está neste Mac e sem convite na atividade: não entra, deixa a sessão e avisa")
    func unknownBoardWithoutInvitationLeavesTheSession() async throws {
        let room = try await Self.makeRoom()
        defer { room.env.removeFiles() }
        let link = FakeLiveSessionLink(boardID: BoardID())

        await room.live.accept(link)

        #expect(link.joined == 0)
        #expect(link.left == 1)
        #expect(room.live.phase == .idle)
        #expect(room.live.presence == nil)
        let notice = try #require(room.env.controller.notices.last)
        #expect(notice.title == "Live Share")
        #expect(notice.message == "Este mural ainda não está neste Mac. Peça a quem compartilhou para convidar você.")
        #expect(notice.boardID == nil)
        #expect(notice.requestAccessURL == nil)
        await room.env.finish()
    }

    @Test("Sessão que termina: a presença some, a fase volta a idle e o mural sai de liveBoards")
    func invalidatedSessionClearsEverything() async throws {
        let room = try await Self.makeRoom()
        defer { room.env.removeFiles() }
        let link = await Self.goLive(room)
        _ = Self.verifyGuest(room, on: link)
        #expect(room.env.controller.liveBoards == [room.id])

        link.simulate(state: .invalidated)

        #expect(room.live.presence == nil)
        #expect(room.live.phase == .idle)
        #expect(!room.live.isLive(room.id))
        #expect(room.live.peers(on: room.id).isEmpty)
        #expect(room.env.controller.liveBoards.isEmpty)
        await room.env.finish()
    }

    @Test("Fechar a aba do mural: sai da sessão, a fase volta a idle e liveBoards fica vazio")
    func closingTheTabLeavesTheSession() async throws {
        let room = try await Self.makeRoom()
        defer { room.env.removeFiles() }
        let link = await Self.goLive(room)
        let guest = Self.verifyGuest(room, on: link)
        let tab = try #require(room.env.tabs.tab(for: room.id))

        room.env.tabs.close(tab.id)

        #expect(link.left == 1)
        #expect(link.events.last == .init(event: .bye, recipients: .only([guest])))
        #expect(room.live.phase == .idle)
        #expect(room.live.presence == nil)
        #expect(room.env.controller.liveBoards.isEmpty)
        await room.env.finish()
    }

    @Test("leave() manda a despedida só aos conferidos; sem ninguém conferido, só deixa a sessão")
    func leavingSaysGoodbyeToVerifiedPeersOnly() async throws {
        let room = try await Self.makeRoom()
        defer { room.env.removeFiles() }
        let alone = await Self.goLive(room)
        let aloneEvents = alone.events

        room.live.leave()

        #expect(alone.left == 1)
        #expect(alone.events == aloneEvents, "ninguém conferido: nada a dizer")
        #expect(room.live.phase == .idle)

        let link = await Self.goLive(room)
        let guest = Self.verifyGuest(room, on: link)
        link.simulate(.hello(Self.hello(room.id, user: "desconhecido")), from: UUID())

        room.live.leave()

        #expect(link.left == 1)
        #expect(link.events.last == .init(event: .bye, recipients: .only([guest])))
        #expect(room.live.phase == .idle)
        #expect(room.live.presence == nil)
        #expect(room.env.controller.liveBoards.isEmpty)
        await room.env.finish()
    }

    // MARK: Começar

    @Test("start pede ao sistema a atividade do mural certo, com o endereço do convite; um erro vira aviso do Live Share")
    func startAsksTheStarterForTheRightActivity() async throws {
        let room = try await Self.makeRoom()
        defer { room.env.removeFiles() }

        await room.live.start(room.id)

        let activity = try #require(room.starter.requested.first)
        #expect(room.starter.requested.count == 1)
        #expect(activity.boardID == room.id)
        #expect(activity.shareURL == room.env.controller.shareStates[room.id]?.url)
        #expect(room.live.phase == .idle, "a sessão chega depois, por listen()")
        #expect(room.env.controller.notices.isEmpty)

        room.starter.error = LiveShareError.noWindow
        await room.live.start(room.id)

        let notice = try #require(room.env.controller.notices.last)
        #expect(notice.title == "Live Share")
        #expect(notice.message == "Não foi possível começar o Live Share: Abra a janela do Mural para começar o Live Share.")
        await room.env.finish()
    }

    // MARK: Mudanças do mural

    @Test("Gravação local na aba ao vivo: o aviso .saved vai só às pessoas conferidas")
    func localSaveTellsOnlyVerifiedPeers() async throws {
        let room = try await Self.makeRoom()
        defer { room.env.removeFiles() }
        let link = await Self.goLive(room)
        let guest = Self.verifyGuest(room, on: link)
        link.simulate(.hello(Self.hello(room.id, user: "desconhecido")), from: UUID())
        let tab = try #require(room.env.tabs.tab(for: room.id))
        await waitUntil("a aba carregar") { tab.session.model != nil }

        try await Self.saveEdit(in: tab)

        await waitUntil("o aviso de gravação") { !link.saved(room.id).isEmpty }
        #expect(link.saved(room.id).allSatisfy { $0.recipients == .only([guest]) })
        await room.env.finish()
    }

    @Test("Aviso .saved de pessoa conferida: a edição do outro Mac chega à aba sem fetch() explícito")
    func savedNoticeBringsTheRemoteEditToTheTab() async throws {
        let room = try await Self.makeRoom()
        defer { room.env.removeFiles() }
        let name = try await room.env.diskManifest(room.id).name
        let remote = try await RemoteMac.join(
            boardID: room.id, name: name, cloud: room.env.cloud, root: room.env.directory.appendingPathComponent("OutroMac"))
        let link = await Self.goLive(room)
        let guest = Self.verifyGuest(room, on: link)
        let tab = try #require(room.env.tabs.tab(for: room.id))
        await waitUntil("a aba carregar") { tab.session.model != nil }
        let arrived = Self.note("do outro Mac")
        try await remote.edit { $0.add(arrived) }
        #expect(tab.session.model?.board.item(id: arrived.id) == nil, "sem aviso, a aba ainda não tem a edição")

        link.simulate(.saved(boardID: room.id), from: guest)

        await waitUntil("a edição do outro Mac chegar à aba") { tab.session.model?.board.item(id: arrived.id) != nil }
        await room.env.finish()
    }

    // MARK: Convite, busca de reserva e sessões juntas

    @Test("Convidado que aceitou depois de a sessão começar: o hello não conferido faz reler o convite, e ele passa a ser conferido")
    func lateGuestIsVerifiedAfterTheInvitationIsReread() async throws {
        let room = try await Self.makeRoom(invitesGuest: false)
        defer { room.env.removeFiles() }
        let link = await Self.goLive(room)
        try await room.env.controller.inviteTestGuest(to: .saved(room.id))
        let guest = UUID()

        link.simulate(.hello(Self.hello(room.id, user: CloudSyncController.testGuest, name: "Bia")), from: guest)

        #expect(room.live.peers(on: room.id).isEmpty, "a presença ainda tem o convite de antes")
        #expect(room.live.presence?.unverifiedCount == 1)
        await waitUntil("o convite ser relido e o convidado conferido") { room.live.peers(on: room.id).map(\.id) == [guest] }
        #expect(room.env.controller.liveBoards == [room.id])
        await room.env.finish()
    }

    @Test("Busca de reserva: só roda com pessoa conferida, e traz a edição do outro Mac mesmo sem o aviso .saved")
    func fallbackFetchRunsOnlyWithVerifiedPeers() async throws {
        let room = try await Self.makeRoom(fallbackFetchInterval: .milliseconds(100))
        defer { room.env.removeFiles() }
        let name = try await room.env.diskManifest(room.id).name
        let remote = try await RemoteMac.join(
            boardID: room.id, name: name, cloud: room.env.cloud, root: room.env.directory.appendingPathComponent("OutroMac"))
        let link = await Self.goLive(room)
        link.simulate(.hello(Self.hello(room.id, user: "desconhecido")), from: UUID())
        let tab = try #require(room.env.tabs.tab(for: room.id))
        await waitUntil("a aba carregar") { tab.session.model != nil }
        // O hello não conferido relê o convite (uma busca): espera passar, para a edição não chegar por ela.
        try await Task.sleep(for: .milliseconds(300))
        let arrived = Self.note("do outro Mac")
        try await remote.edit { $0.add(arrived) }

        try await Task.sleep(for: .milliseconds(500))
        #expect(tab.session.model?.board.item(id: arrived.id) == nil, "ninguém conferido: a busca de reserva não roda")

        _ = Self.verifyGuest(room, on: link)

        await waitUntil("a busca de reserva trazer a edição") { tab.session.model?.board.item(id: arrived.id) != nil }
        await room.env.finish()
    }

    @Test("Duas sessões que chegam juntas: só uma continua, entrou na sessão, e a outra é deixada")
    func sessionsArrivingTogetherKeepOnlyOne() async throws {
        let room = try await Self.makeRoom()
        defer { room.env.removeFiles() }
        let first = FakeLiveSessionLink(boardID: room.id)
        let second = FakeLiveSessionLink(boardID: room.id)

        let pending = Task { await room.live.accept(first) }
        await room.live.accept(second)
        await pending.value

        let links = [first, second]
        #expect(room.live.phase == .live(room.id))
        #expect(links.filter { $0.left == 0 }.count == 1, "só uma sessão continua")
        #expect(links.first { $0.left == 0 }?.joined == 1, "a que continua entrou na sessão")
        await room.env.finish()
    }

    // MARK: Relatos locais

    @Test("Ponteiro em rajada: poucos envios, o último valor ao fim, e nil avisa o fim pelo canal confiável uma vez só")
    func pointerBurstIsThrottled() async throws {
        let room = try await Self.makeRoom()
        defer { room.env.removeFiles() }
        let link = await Self.goLive(room)
        let guest = Self.verifyGuest(room, on: link)
        let started = ContinuousClock.now

        for step in 0..<30 {
            room.live.pointerMoved(to: CGPoint(x: Double(step), y: Double(step) * 2), in: room.id)
            try await Task.sleep(for: .milliseconds(5))
        }

        let last = FakeLiveSessionLink.SentMotion(motion: .pointer(boardID: room.id, x: 29, y: 58), recipients: .only([guest]))
        await waitUntil("o último valor do ponteiro") { link.motions.last == last }
        let elapsed = ContinuousClock.now - started
        #expect(!link.motions.isEmpty)
        #expect(Double(link.motions.count) <= elapsed / .milliseconds(50) + 2, "no máximo um envio por intervalo")
        #expect(link.motions.count < 30, "as repetições foram juntadas")

        room.live.pointerMoved(to: nil, in: room.id)
        #expect(link.events.last == .init(event: .pointerLeft(boardID: room.id), recipients: .only([guest])))
        let sent = link.events.count
        room.live.pointerMoved(to: nil, in: room.id)
        #expect(link.events.count == sent, "o fim não se repete")
        await room.env.finish()
    }

    @Test("Arrasto: sai o .drag pelo canal sem garantia, vence o ponteiro no mesmo instante, e nil manda .dragEnded")
    func dragIsSentAndEnded() async throws {
        let room = try await Self.makeRoom()
        defer { room.env.removeFiles() }
        let link = await Self.goLive(room)
        let guest = Self.verifyGuest(room, on: link)
        let sentBefore = link.events.count
        room.live.dragChanged(nil, in: room.id)
        #expect(link.events.count == sentBefore, "sem arrasto enviado, não há fim a avisar")

        let drag = LiveDrag(kind: .item, id: UUID(), x: 10, y: 20)
        room.live.dragChanged(drag, in: room.id)
        let expected = FakeLiveSessionLink.SentMotion(motion: .drag(boardID: room.id, drag: drag), recipients: .only([guest]))
        await waitUntil("o arrasto") { link.motions.last == expected }

        room.live.dragChanged(nil, in: room.id)
        #expect(link.events.last == .init(event: .dragEnded(boardID: room.id), recipients: .only([guest])))

        // Ponteiro e arrasto no mesmo instante: vai só o arrasto, para o ponteiro não limpar o arrasto de quem recebe.
        let before = link.motions.count
        let second = LiveDrag(kind: .freeText, id: UUID(), x: 30, y: 40)
        room.live.pointerMoved(to: CGPoint(x: 5, y: 5), in: room.id)
        room.live.dragChanged(second, in: room.id)
        await waitUntil("o segundo arrasto") { link.motions.count > before }
        try await Task.sleep(for: .milliseconds(200))
        #expect(link.motions.dropFirst(before).map(\.motion) == [.drag(boardID: room.id, drag: second)])
        await room.env.finish()
    }

    @Test("Foco: guardado antes de entrar vai no hello; mudança ao vivo manda .focus; foco igual não repete")
    func focusIsStoredAndSent() async throws {
        let room = try await Self.makeRoom()
        defer { room.env.removeFiles() }
        let editing = LiveFocus(itemID: UUID(), isEditing: true)
        room.live.focusChanged(editing, in: room.id)

        let link = await Self.goLive(room)

        let hello = Self.hello(room.id, user: CloudSyncController.testUser, name: "Ana", focus: editing, reply: true)
        #expect(link.events == [.init(event: .hello(hello), recipients: .all)], "o foco de antes de entrar foi junto")

        let guest = Self.verifyGuest(room, on: link)
        let viewing = LiveFocus(itemID: editing.itemID, isEditing: false)
        room.live.focusChanged(viewing, in: room.id)
        #expect(link.events.last == .init(event: .focus(boardID: room.id, focus: viewing), recipients: .only([guest])))

        let sent = link.events.count
        room.live.focusChanged(viewing, in: room.id)
        #expect(link.events.count == sent, "o mesmo foco não é enviado de novo")

        room.live.focusChanged(nil, in: room.id)
        #expect(link.events.last == .init(event: .focus(boardID: room.id, focus: nil), recipients: .only([guest])))
        await room.env.finish()
    }

    #if DEBUG
    // MARK: Demonstração

    @Test("Demonstração: Bia e Caio aparecem conferidos, o Caio com o foco no cartão, e leave() volta a idle")
    func demoShowsBothPeopleAndLeaves() async throws {
        let room = try await Self.makeRoom()
        defer { room.env.removeFiles() }
        let tab = try #require(room.env.tabs.open(.saved(room.id), title: "Ao vivo"))
        await waitUntil("a aba carregar") { tab.session.model != nil }
        let card = try #require(tab.session.model?.rootItems.first)
        let starter = LiveShareDemoStarter(tabs: room.env.tabs)
        starter.controller = room.live

        let outcome = try await starter.start(MuralLiveActivity(boardID: room.id, shareURL: nil), in: nil)

        #expect(starter.isInCall)
        #expect(outcome == .started)
        #expect(room.live.phase == .live(room.id))
        let peers = room.live.peers(on: room.id)
        #expect(peers.count == 2)
        let bia = try #require(peers.first { $0.id == LiveShareDemoLink.bia })
        let caio = try #require(peers.first { $0.id == LiveShareDemoLink.caio })
        #expect(bia.isVerified && caio.isVerified)
        #expect(bia.name == CloudSyncController.testGuest, "vale o nome do convite, não o que o Mac da Bia diz")
        #expect(caio.name == CloudSyncController.testUser, "o dono do mural também é nomeado pelo convite")
        #expect(bia.focus == nil)
        #expect(caio.focus == LiveFocus(itemID: card.id, isEditing: true))
        #expect(room.env.controller.liveBoards == [room.id])

        await waitUntil("o ponteiro da Bia e o arrasto do Caio") {
            let now = room.live.peers(on: room.id)
            return now.first { $0.id == LiveShareDemoLink.bia }?.pointer != nil
                && now.first { $0.id == LiveShareDemoLink.caio }?.drag?.id == card.id
        }

        room.live.leave()

        #expect(room.live.phase == .idle)
        #expect(room.live.presence == nil)
        #expect(room.env.controller.liveBoards.isEmpty)
        await room.env.finish()
    }

    @Test("Demonstração, a sessão sozinha: o hello dos dois, o movimento com o arrasto do cartão e leave() que para tudo")
    func demoLinkTalksUntilItLeaves() async throws {
        let boardID = BoardID()
        let card = Self.note("um")
        let link = LiveShareDemoLink(activity: MuralLiveActivity(boardID: boardID, shareURL: nil), card: card)
        let recorder = DemoRecorder()
        link.connect(recorder.handlers)
        #expect(link.state == .waiting)

        link.join()

        #expect(link.state == .joined)
        #expect(recorder.states == [.joined])
        #expect(recorder.participants == [Set([LiveShareDemoLink.bia, LiveShareDemoLink.caio])])
        let biaHello = Self.hello(boardID, user: CloudSyncController.testGuest, name: "Bia")
        let caioHello = Self.hello(
            boardID, user: CloudSyncController.testUser, name: "Caio", focus: LiveFocus(itemID: card.id, isEditing: true))
        #expect(recorder.events.map { $0.event } == [.hello(biaHello), .hello(caioHello)])
        #expect(recorder.events.map { $0.peer } == [LiveShareDemoLink.bia, LiveShareDemoLink.caio])

        await waitUntil("o ponteiro da Bia e o arrasto do Caio") {
            recorder.motions.contains { $0.peer == LiveShareDemoLink.bia } && !recorder.drags.isEmpty
        }
        #expect(recorder.motions.allSatisfy { $0.peer == LiveShareDemoLink.bia || $0.peer == LiveShareDemoLink.caio })
        let drag = try #require(recorder.drags.first)
        #expect(drag.kind == .item)
        #expect(drag.id == card.id)
        #expect((card.position.x...(card.position.x + 120)).contains(drag.x))
        #expect((card.position.y...(card.position.y + 60)).contains(drag.y))

        link.leave()

        #expect(link.state == .invalidated)
        #expect(recorder.states == [.joined, .invalidated])
        let sent = recorder.motions.count
        try await Task.sleep(for: .milliseconds(250))
        #expect(recorder.motions.count == sent, "a tarefa parou")
        link.leave()
        #expect(recorder.states == [.joined, .invalidated], "sair de novo não avisa de novo")
    }

    @Test("Demonstração sem cartão solto: só o ponteiro da Bia se mexe, e o Caio chega sem foco")
    func demoWithoutACardMovesOnlyBiasPointer() async throws {
        let boardID = BoardID()
        let link = LiveShareDemoLink(activity: MuralLiveActivity(boardID: boardID, shareURL: nil), card: nil)
        let recorder = DemoRecorder()
        link.connect(recorder.handlers)

        link.join()
        await waitUntil("alguns passos do ponteiro") { recorder.motions.count >= 4 }
        link.leave()

        #expect(recorder.motions.allSatisfy { $0.peer == LiveShareDemoLink.bia })
        #expect(recorder.drags.isEmpty)
        let biaHello = Self.hello(boardID, user: CloudSyncController.testGuest, name: "Bia")
        let caioHello = Self.hello(boardID, user: CloudSyncController.testUser, name: "Caio")
        #expect(recorder.events.map { $0.event } == [.hello(biaHello), .hello(caioHello)], "sem arrasto, nem fim de arrasto")
    }

    @Test("Demonstração: o roteiro segue o tempo, com uma volta do ponteiro a cada 4 s e um arrasto de 2 s a cada 6 s")
    func demoScriptFollowsTheTime() {
        func isClose(_ point: CGPoint, _ x: Double, _ y: Double) -> Bool {
            abs(point.x - x) < 0.001 && abs(point.y - y) < 0.001
        }
        #expect(isClose(LiveShareDemoLink.biaPointer(at: 0), 520, 260))
        #expect(isClose(LiveShareDemoLink.biaPointer(at: 1), 360, 380))
        #expect(isClose(LiveShareDemoLink.biaPointer(at: 2), 200, 260))
        #expect(isClose(LiveShareDemoLink.biaPointer(at: 4), 520, 260), "uma volta inteira a cada 4 s")
        #expect(LiveShareDemoLink.caioDragProgress(at: 0) == 0)
        #expect(LiveShareDemoLink.caioDragProgress(at: 1) == 0.5)
        #expect(LiveShareDemoLink.caioDragProgress(at: 2) == nil, "depois de 2 s ele larga o cartão")
        #expect(LiveShareDemoLink.caioDragProgress(at: 5.9) == nil)
        #expect(LiveShareDemoLink.caioDragProgress(at: 6) == 0, "e arrasta de novo a cada 6 s")
        #expect(LiveShareDemoLink.caioDragProgress(at: 7) == 0.5)
    }
    #endif

    // MARK: Apoio

    /// O dono com o convidado de teste convidado, o controlador do Live Share e um início falso.
    private struct Room {
        let env: SyncEnvironment
        let live: LiveShareController
        let starter: FakeStarter
        let id: BoardID
    }

    /// - Parameter invitesGuest: `false` deixa o mural no iCloud sem convite: o convidado de teste é convidado depois, pelo teste.
    private static func makeRoom(invitesGuest: Bool = true, fallbackFetchInterval: Duration = .seconds(60)) async throws -> Room {
        let env = try SyncEnvironment()
        let id = try await env.seed(name: "Ao vivo", items: [note("um")])
        await env.controller.start()
        if invitesGuest {
            try await env.controller.inviteTestGuest(to: .saved(id))
        } else {
            try await env.controller.putInCloud(.saved(id))
        }
        let starter = FakeStarter()
        let live = LiveShareController(
            sync: env.controller, tabs: env.tabs, starter: starter, motionInterval: .milliseconds(50),
            fallbackFetchInterval: fallbackFetchInterval, displayName: "Ana")
        return Room(env: env, live: live, starter: starter, id: id)
    }

    /// Aceita uma sessão do mural da sala e a faz entrar (`.joined`).
    private static func goLive(_ room: Room) async -> FakeLiveSessionLink {
        let link = FakeLiveSessionLink(boardID: room.id)
        await room.live.accept(link)
        link.simulate(state: .joined)
        return link
    }

    /// O convidado do convite diz quem é e passa a ser conferido.
    /// - Returns: o `Participant.id` dele na sessão.
    private static func verifyGuest(_ room: Room, on link: FakeLiveSessionLink) -> UUID {
        let guest = UUID()
        link.simulate(.hello(hello(room.id, user: CloudSyncController.testGuest, name: "Bia")), from: guest)
        return guest
    }

    private static func hello(
        _ id: BoardID, user: String?, name: String? = nil, focus: LiveFocus? = nil, reply: Bool = false
    ) -> LiveHello {
        LiveHello(boardID: id, userRecordName: user, displayName: name, focus: focus, replyRequested: reply)
    }

    private static func note(_ text: String) -> BoardItem {
        BoardItem(
            kind: .sticky, title: ContentClassifier.title(forText: text), createdAt: fixedDate, position: BoardPoint(x: 10, y: 20),
            text: text, stickyColor: .yellow)
    }

    /// Uma gravação local do mural da aba, como a de quem digita: entra no disco e agenda o envio ao iCloud.
    @discardableResult
    private static func saveEdit(in tab: BoardTab, text: String = "escrito aqui") async throws -> BoardItem {
        let model = try #require(tab.session.model)
        let added = try #require(model.importText(text, as: .text))
        tab.session.captureBoardIfNeeded()
        await tab.session.flushAndPrepareToLeave()
        return added
    }
}

/// A sessão falsa: guarda o que o controlador mandou e simula o que a sessão avisaria.
@MainActor
private final class FakeLiveSessionLink: LiveSessionLink {
    struct SentEvent: Equatable {
        var event: LiveEvent
        var recipients: LiveRecipients
    }

    struct SentMotion: Equatable {
        var motion: LiveMotion
        var recipients: LiveRecipients
    }

    let activity: MuralLiveActivity
    private(set) var state: LiveSessionState = .waiting
    private(set) var joined = 0
    private(set) var left = 0
    private(set) var events: [SentEvent] = []
    private(set) var motions: [SentMotion] = []
    private var handlers: LiveSessionHandlers?

    init(boardID: BoardID, shareURL: URL? = nil) {
        activity = MuralLiveActivity(boardID: boardID, shareURL: shareURL)
    }

    func connect(_ handlers: LiveSessionHandlers) {
        self.handlers = handlers
    }

    func join() {
        joined += 1
    }

    func leave() {
        left += 1
    }

    func send(_ event: LiveEvent, to recipients: LiveRecipients) {
        events.append(SentEvent(event: event, recipients: recipients))
    }

    func send(_ motion: LiveMotion, to recipients: LiveRecipients) {
        motions.append(SentMotion(motion: motion, recipients: recipients))
    }

    /// Os avisos de gravação enviados para o mural.
    func saved(_ id: BoardID) -> [SentEvent] {
        events.filter { $0.event == .saved(boardID: id) }
    }

    // MARK: O que a sessão avisaria

    func simulate(state: LiveSessionState) {
        self.state = state
        handlers?.stateChanged(state)
    }

    func simulate(participants: Set<UUID>) {
        handlers?.participantsChanged(participants)
    }

    func simulate(_ event: LiveEvent, from peer: UUID) {
        handlers?.event(event, peer)
    }

    func simulate(_ motion: LiveMotion, from peer: UUID) {
        handlers?.motion(motion, peer)
    }
}

/// O início falso: guarda as atividades pedidas e, se mandado, falha.
@MainActor
private final class FakeStarter: LiveActivityStarter {
    var isInCall: Bool
    var error: (any Error)?
    private(set) var requested: [MuralLiveActivity] = []

    init(isInCall: Bool = false) {
        self.isInCall = isInCall
    }

    func start(_ activity: MuralLiveActivity, in window: NSWindow?) async throws -> LiveStartOutcome {
        requested.append(activity)
        if let error { throw error }
        return .started
    }
}

#if DEBUG
/// Anota o que a sessão da demonstração avisa, no lugar do controlador.
@MainActor
private final class DemoRecorder {
    struct Event {
        var event: LiveEvent
        var peer: UUID
    }

    struct Motion {
        var motion: LiveMotion
        var peer: UUID
    }

    private(set) var states: [LiveSessionState] = []
    private(set) var participants: [Set<UUID>] = []
    private(set) var events: [Event] = []
    private(set) var motions: [Motion] = []

    /// Os arrastos recebidos, na ordem.
    var drags: [LiveDrag] {
        motions.compactMap { entry -> LiveDrag? in
            if case .drag(_, let drag) = entry.motion { drag } else { nil }
        }
    }

    var handlers: LiveSessionHandlers {
        LiveSessionHandlers(
            stateChanged: { [self] in states.append($0) },
            participantsChanged: { [self] in participants.append($0) },
            event: { [self] in events.append(Event(event: $0, peer: $1)) },
            motion: { [self] in motions.append(Motion(motion: $0, peer: $1)) })
    }
}
#endif
