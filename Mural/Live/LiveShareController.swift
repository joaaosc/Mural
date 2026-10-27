import AppKit
import CoreGraphics
import Foundation
import GroupActivities
import MuralKit
import MuralSync
import Observation

/// O controlador do Live Share, um só no nível do app: dono da sessão do SharePlay, da presença das pessoas e do que a pessoa deste
/// Mac envia (ponteiro, arrasto, foco, aviso de gravação). O conteúdo do mural não passa por aqui: continua indo pelo iCloud, e as
/// mensagens da sessão só dizem quando buscar.
///
/// Ocupa os ganchos de um ouvinte só: `CloudSyncController.onBoardSent`, `CloudSyncController.onBoardLeftCloud` e
/// `MuralTabs.onBoardClosed`. Só uma sessão por vez; uma nova substitui a que estava em andamento.
///
/// Só quem foi conferido contra o convite do mural (`LivePresence`) aparece, é ouvido e recebe mensagens.
@MainActor
@Observable
final class LiveShareController {
    enum Phase: Equatable {
        case idle
        case connecting(BoardID)
        case live(BoardID)
    }

    private(set) var phase: Phase = .idle
    /// A presença do Live Share em andamento; `nil` sem sessão.
    private(set) var presence: LivePresence?

    private let sync: CloudSyncController
    private let tabs: MuralTabs
    private let starter: any LiveActivityStarter
    private let motionInterval: Duration
    private let fallbackFetchInterval: Duration
    private let displayName: String?
    @ObservationIgnored private var link: (any LiveSessionLink)?
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var motionTask: Task<Void, Never>?
    @ObservationIgnored private var fallbackTask: Task<Void, Never>?
    @ObservationIgnored private var rosterTask: Task<Void, Never>?
    @ObservationIgnored private var pendingPointer: CGPoint?
    @ObservationIgnored private var pendingDrag: LiveDrag?
    @ObservationIgnored private var lastMotionAt: ContinuousClock.Instant?
    /// Já foi um ponteiro / um arrasto que ainda não terminou: só então o fim (`pointerLeft`, `dragEnded`) precisa ser avisado.
    @ObservationIgnored private var isSendingPointer = false
    @ObservationIgnored private var isSendingDrag = false
    /// O foco local de cada mural, guardado mesmo fora do Live Share para ir no `hello` de quem entra.
    @ObservationIgnored private var localFocus: [BoardID: LiveFocus] = [:]
    @ObservationIgnored private var localUserRecordName: String?
    /// Conta as tentativas de `accept`: uma tentativa que acordou depois de `leave()` ou de uma sessão nova sabe que não é mais a atual.
    @ObservationIgnored private var attempt = 0

    /// - Parameters:
    ///   - motionInterval: o menor intervalo entre dois envios de movimento (ponteiro ou arrasto).
    ///   - fallbackFetchInterval: de quanto em quanto tempo se busca no iCloud enquanto há alguém conferido, caso um aviso `saved` se perca.
    ///   - displayName: o nome que este Mac diz ter no `hello`; só vale para quem o convite não nomeia.
    init(
        sync: CloudSyncController, tabs: MuralTabs, starter: any LiveActivityStarter = SharePlayStarter(),
        motionInterval: Duration = .milliseconds(66), fallbackFetchInterval: Duration = .seconds(20),
        displayName: String? = NSFullUserName()
    ) {
        self.sync = sync
        self.tabs = tabs
        self.starter = starter
        self.motionInterval = motionInterval
        self.fallbackFetchInterval = fallbackFetchInterval
        self.displayName = displayName.flatMap { $0.isEmpty ? nil : $0 }
        sync.onBoardSent = { [weak self] id in self?.boardWasSent(id) }
        sync.onBoardLeftCloud = { [weak self] id in self?.boardBecameUnavailable(id) }
        tabs.onBoardClosed = { [weak self] id in self?.boardBecameUnavailable(id) }
    }

    // MARK: Leitura

    /// Há uma chamada do FaceTime em que o Live Share começa direto.
    var isInCall: Bool { starter.isInCall }

    /// O mural está em Live Share. Lê só a fase: o botão da barra não redesenha a cada movimento de ponteiro.
    func isLive(_ boardID: BoardID) -> Bool {
        phase == .live(boardID)
    }

    /// As pessoas conferidas deste mural; vazio quando ele não é o do Live Share em andamento.
    func peers(on boardID: BoardID) -> [LivePeer] {
        guard let presence, presence.boardID == boardID else { return [] }
        return presence.visiblePeers
    }

    // MARK: Sessão

    /// Passa a receber as sessões do SharePlay, que chegam quando alguém começa o Live Share (aqui ou em outro Mac). Uma vez só.
    func listen() {
        guard listenTask == nil else { return }
        listenTask = Task { @MainActor [weak self] in
            for await session in MuralLiveActivity.sessions() {
                guard let self else { return }
                await self.accept(GroupSessionLink(session: session))
            }
        }
    }

    /// Recebe uma sessão: abre o mural, liga a presença e entra. Uma sessão nova substitui a que estava em andamento. Se o mural
    /// não está neste Mac e não dá para trazê-lo, a pessoa é avisada e a sessão é deixada. Se a fase mudar no meio (outra sessão ou
    /// `leave()`), esta tentativa desiste e deixa a sessão.
    func accept(_ link: any LiveSessionLink) async {
        if phase != .idle || self.link != nil { leave() }
        attempt &+= 1
        let token = attempt
        let board = link.activity.boardID
        phase = .connecting(board)

        guard await openBoard(for: link.activity) else {
            link.leave()
            if isConnecting(board, token: token) { tearDown() }
            return
        }
        guard isConnecting(board, token: token) else { return link.leave() }
        let userRecordName = await sync.currentUserRecordName()
        guard isConnecting(board, token: token) else { return link.leave() }
        if sync.shareStates[board] == nil {
            await sync.refreshShare(for: board)
            guard isConnecting(board, token: token) else { return link.leave() }
        }

        localUserRecordName = userRecordName
        self.link = link
        presence = LivePresence(boardID: board, roster: LiveRoster(share: sync.shareStates[board], localUserRecordName: userRecordName))
        phase = .live(board)
        // Os avisos antes do `join()`; os de uma sessão antiga são ignorados.
        link.connect(handlers(for: link))
        link.join()
    }

    /// Pede ao sistema que comece o Live Share do mural (a sessão chega depois por `listen()`). Um erro vira aviso.
    func start(_ boardID: BoardID) async {
        let activity = MuralLiveActivity(boardID: boardID, shareURL: sync.shareStates[boardID]?.url)
        do {
            _ = try await starter.start(activity, in: tabs.window)
        } catch {
            sync.postLiveShareNotice("Não foi possível começar o Live Share: \(error.localizedDescription)")
        }
    }

    /// Sai do Live Share: avisa as pessoas conferidas e deixa a sessão.
    func leave() {
        if let link {
            if let presence, !presence.verifiedIDs.isEmpty { link.send(.bye, to: .only(presence.verifiedIDs)) }
            link.leave()
        }
        tearDown()
    }

    // MARK: Relatos locais

    /// O ponteiro da pessoa: `nil` quando saiu do mural. Os movimentos em rajada viram um envio por `motionInterval`, com o último valor.
    func pointerMoved(to point: CGPoint?, in boardID: BoardID) {
        guard isLive(boardID) else { return }
        guard let point else {
            pendingPointer = nil
            if isSendingPointer {
                isSendingPointer = false
                sendToVerified(.pointerLeft(boardID: boardID))
            }
            return
        }
        guard hasVerifiedPeers else { return }
        pendingPointer = point
        scheduleMotion()
    }

    /// O elemento que a pessoa arrasta: `nil` quando soltou. Mesmo ritmo do ponteiro.
    func dragChanged(_ drag: LiveDrag?, in boardID: BoardID) {
        guard isLive(boardID) else { return }
        guard let drag else {
            pendingDrag = nil
            if isSendingDrag {
                isSendingDrag = false
                sendToVerified(.dragEnded(boardID: boardID))
            }
            return
        }
        guard hasVerifiedPeers else { return }
        pendingDrag = drag
        scheduleMotion()
    }

    /// O cartão aberto: guardado mesmo sem Live Share (vai no `hello` de quem entra) e avisado quando muda com o mural ao vivo.
    func focusChanged(_ focus: LiveFocus?, in boardID: BoardID) {
        guard localFocus[boardID] != focus else { return }
        localFocus[boardID] = focus
        guard isLive(boardID) else { return }
        sendToVerified(.focus(boardID: boardID, focus: focus))
    }

    // MARK: Abrir o mural

    /// Deixa o mural da atividade aberto numa aba: o que já está neste Mac e no iCloud abre direto; o que não está é aceito pelo
    /// convite do iCloud, quando a atividade o traz.
    /// - Returns: o mural está aberto neste Mac.
    private func openBoard(for activity: MuralLiveActivity) async -> Bool {
        let id = activity.boardID
        await sync.start()
        if let name = await cloudBoardName(id) {
            await showTab(for: id, title: name)
            return true
        }
        if let url = activity.shareURL { return await sync.acceptShare(at: url) }
        sync.postLiveShareNotice("Este mural ainda não está neste Mac. Peça a quem compartilhou para convidar você.")
        return false
    }

    /// O nome do mural no manifesto, se ele está neste Mac e no iCloud (`cloud` no manifesto); `nil` se não está.
    private func cloudBoardName(_ id: BoardID) async -> String? {
        guard let manifest = (try? await tabs.registry.library.open(.saved(id)))?.manifest, manifest.cloud != nil else { return nil }
        return manifest.name
    }

    /// Abre a aba do mural e traz a janela. Se o app foi aberto pela chamada e ainda não tem janela, espera até uns 3 s por ela, para
    /// a aba não tomar o lugar das abas restauradas.
    private func showTab(for id: BoardID, title: String) async {
        if tabs.window == nil, tabs.openMainWindow != nil {
            tabs.showWindow()
            var waited = 0
            while tabs.window == nil, waited < 30 {
                try? await Task.sleep(for: .milliseconds(100))
                waited += 1
            }
        }
        tabs.open(.saved(id), title: title)
        tabs.showWindow()
    }

    private func isConnecting(_ board: BoardID, token: Int) -> Bool {
        attempt == token && phase == .connecting(board)
    }

    // MARK: Avisos da sessão

    private func handlers(for link: any LiveSessionLink) -> LiveSessionHandlers {
        LiveSessionHandlers(
            stateChanged: { [weak self, weak link] state in
                guard let self, let link, self.link === link else { return }
                self.sessionStateChanged(state)
            },
            participantsChanged: { [weak self, weak link] ids in
                guard let self, let link, self.link === link else { return }
                self.participantsChanged(ids)
            },
            event: { [weak self, weak link] event, peer in
                guard let self, let link, self.link === link else { return }
                self.receive(event, from: peer)
            },
            motion: { [weak self, weak link] motion, peer in
                guard let self, let link, self.link === link else { return }
                self.mutatePresence { $0.receive(motion, from: peer) }
            })
    }

    private func sessionStateChanged(_ state: LiveSessionState) {
        switch state {
        case .waiting: break
        case .joined: sendHello(replyRequested: true, to: .all)
        case .invalidated: tearDown()
        }
    }

    /// Quem chegou à sessão recebe o `hello` daqui; quem saiu deixa a presença.
    private func participantsChanged(_ ids: Set<UUID>) {
        guard let arrived = mutatePresence({ $0.setParticipants(ids) }) else { return }
        if !arrived.isEmpty { sendHello(replyRequested: false, to: .only(arrived)) }
        updateLiveMode()
    }

    private func receive(_ event: LiveEvent, from peer: UUID) {
        guard let reaction = mutatePresence({ $0.receive(event, from: peer) }) else { return }
        if let target = reaction.replyHelloTo { sendHello(replyRequested: false, to: .only([target])) }
        if reaction.fetchRequested { sync.requestFetch() }
        if reaction.needsRosterRefresh { refreshRoster() }
        updateLiveMode()
    }

    private func sendHello(replyRequested: Bool, to recipients: LiveRecipients) {
        guard let link, let board = presence?.boardID else { return }
        let hello = LiveHello(
            boardID: board, userRecordName: localUserRecordName, displayName: displayName, focus: localFocus[board],
            replyRequested: replyRequested)
        link.send(.hello(hello), to: recipients)
    }

    /// Muda a presença só se algo mudou: o Observation avisa a cada atribuição, e a interface não deve redesenhar à toa.
    /// - Returns: o que a mudança devolveu; `nil` sem presença.
    @discardableResult
    private func mutatePresence<Output>(_ change: (inout LivePresence) -> Output) -> Output? {
        guard var updated = presence else { return nil }
        let output = change(&updated)
        if updated != presence { presence = updated }
        return output
    }

    // MARK: Modo ao vivo

    /// Com ao menos uma pessoa conferida o mural entra em `liveBoards` (envio mais rápido ao iCloud) e a busca de reserva roda; sem
    /// ninguém conferido, as duas coisas param.
    private func updateLiveMode() {
        guard let presence else { return }
        let hasVerified = !presence.verifiedIDs.isEmpty
        let boards: Set<BoardID> = hasVerified ? [presence.boardID] : []
        if sync.liveBoards != boards { sync.liveBoards = boards }
        if hasVerified { startFallback() } else { stopFallback() }
    }

    /// A busca de reserva: se um aviso `saved` se perder, o iCloud é lido de tempos em tempos, e o convite também (quem aceitou
    /// depois passa a ser conferido).
    private func startFallback() {
        guard fallbackTask == nil else { return }
        let interval = fallbackFetchInterval
        fallbackTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                await self.fallbackRefresh()
            }
        }
    }

    private func stopFallback() {
        fallbackTask?.cancel()
        fallbackTask = nil
    }

    private func fallbackRefresh() async {
        guard let board = presence?.boardID else { return }
        await sync.fetch()
        guard !Task.isCancelled else { return }
        applyRoster(for: board)
    }

    /// Relê o convite do mural, uma tarefa por vez, e refaz a conferência de quem já disse `hello`.
    private func refreshRoster() {
        guard rosterTask == nil, let board = presence?.boardID else { return }
        rosterTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.sync.refreshShare(for: board)
            guard !Task.isCancelled else { return }
            self.rosterTask = nil
            self.applyRoster(for: board)
        }
    }

    private func applyRoster(for board: BoardID) {
        guard presence?.boardID == board else { return }
        let roster = LiveRoster(share: sync.shareStates[board], localUserRecordName: localUserRecordName)
        mutatePresence { $0.setRoster(roster) }
        updateLiveMode()
    }

    // MARK: Envio

    /// Só quem foi conferido recebe algo: sem ninguém conferido, nada sai.
    private var hasVerifiedPeers: Bool {
        !(presence?.verifiedIDs.isEmpty ?? true)
    }

    private func sendToVerified(_ event: LiveEvent) {
        guard let link, let ids = presence?.verifiedIDs, !ids.isEmpty else { return }
        link.send(event, to: .only(ids))
    }

    /// O mural acabou de enviar mudanças ao iCloud: as pessoas conferidas buscam já.
    private func boardWasSent(_ id: BoardID) {
        guard phase == .live(id) else { return }
        sendToVerified(.saved(boardID: id))
    }

    /// Junta os movimentos: uma tarefa por vez, que espera o que falta de `motionInterval` desde o último envio e manda só o último
    /// valor.
    private func scheduleMotion() {
        guard motionTask == nil else { return }
        motionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if let last = self.lastMotionAt {
                let next = last.advanced(by: self.motionInterval)
                if next > .now { try? await ContinuousClock().sleep(until: next) }
            }
            guard !Task.isCancelled else { return }
            self.motionTask = nil
            self.sendPendingMotion()
        }
    }

    /// Manda o arrasto, se houver, e senão o ponteiro, pelo canal sem garantia. Quem arrasta não manda o ponteiro junto: o ponteiro
    /// limparia o arrasto em quem recebe.
    private func sendPendingMotion() {
        guard case .live(let board) = phase, let link, let ids = presence?.verifiedIDs, !ids.isEmpty else {
            pendingPointer = nil
            pendingDrag = nil
            return
        }
        if let drag = pendingDrag {
            pendingDrag = nil
            pendingPointer = nil
            isSendingDrag = true
            link.send(.drag(boardID: board, drag: drag), to: .only(ids))
        } else if let point = pendingPointer {
            pendingPointer = nil
            isSendingPointer = true
            link.send(.pointer(boardID: board, x: point.x, y: point.y), to: .only(ids))
        } else {
            return
        }
        lastMotionAt = .now
    }

    // MARK: Fim

    /// O mural do Live Share saiu do iCloud ou da janela: a pessoa sai da sessão.
    private func boardBecameUnavailable(_ id: BoardID) {
        guard phase == .connecting(id) || phase == .live(id) else { return }
        leave()
    }

    /// Larga tudo da sessão: tarefas, link, presença, modo ao vivo e o que estava pendente.
    private func tearDown() {
        attempt &+= 1
        motionTask?.cancel()
        motionTask = nil
        stopFallback()
        rosterTask?.cancel()
        rosterTask = nil
        link = nil
        if presence != nil { presence = nil }
        if phase != .idle { phase = .idle }
        if !sync.liveBoards.isEmpty { sync.liveBoards = [] }
        pendingPointer = nil
        pendingDrag = nil
        lastMotionAt = nil
        isSendingPointer = false
        isSendingDrag = false
    }
}
