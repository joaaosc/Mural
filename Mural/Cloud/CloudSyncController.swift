import CloudKit
import Foundation
import MuralKit
import MuralSync
import Observation
import os

/// De onde vem o iCloud desta execução do app.
enum CloudSyncMode: Equatable, Sendable {
    /// Sem sincronização: nenhum motor, nenhum `CKContainer`.
    case off
    /// O iCloud falso, em memória, dos testes (`-uiTesting`).
    case inMemory
    /// O iCloud de verdade. Só com o entitlement de CloudKit.
    case cloudKit
}

/// Um aviso para a pessoa sobre um mural que mudou por causa do iCloud. Texto simples por ora; a Fase 3 refina.
struct CloudSyncNotice: Identifiable, Equatable, Sendable {
    let id = UUID()
    var boardID: BoardID
    var message: String
}

/// O controlador da sincronização no app: monta, para cada banco do iCloud (privado e compartilhado), o coordenador e o motor, liga
/// o coordenador às sessões de janela (`CloudSyncBridge`) e guarda o que a interface mostra (`issues`, `notices`).
///
/// Não decide nada sobre o conteúdo: o que enviar, como juntar e o que apagar são do coordenador. Aqui só se ligam as peças e se
/// dizem ao motor os momentos de buscar e enviar.
@MainActor
@Observable
final class CloudSyncController {
    /// O container do app no iCloud.
    static let containerIdentifier = "iCloud.com.joaocosta.Mural"

    /// O nome do usuário no iCloud falso dos testes.
    nonisolated static let testUser = "ui-test"

    private static let log = Logger(subsystem: "com.joaocosta.Mural", category: "Sincronização")
    private static let scopes: [CloudDatabaseScope] = [.private, .shared]

    private struct Channel {
        var coordinator: BoardSyncCoordinator
        var engine: any CloudSyncEngine
    }

    /// O modo em uso. Pedir `.cloudKit` sem o entitlement dá `.off`: criar o container sem ele encerra o app.
    let mode: CloudSyncMode

    /// O que impede cada mural de sincronizar por inteiro, como os coordenadores o dizem depois do último evento que o controlador
    /// provocou (`start`, `fetch`, `send`, `track`). Mural sem aviso não aparece.
    private(set) var issues: [BoardID: SyncIssue] = [:]

    /// Os avisos de murais que saíram do iCloud, do mais antigo ao mais novo, até a pessoa dispensá-los.
    private(set) var notices: [CloudSyncNotice] = []

    /// O convite de cada mural como a última busca que o trouxe o mandou: quem foi convidado, a permissão e o endereço. Convite
    /// apagado (o dono parou de compartilhar) ou mural que saiu do iCloud neste Mac sai daqui. A interface de compartilhamento o usa.
    private(set) var shareStates: [BoardID: ShareSummary] = [:]

    /// O controlador do app, para quem não tem como recebê-lo pelo construtor (o delegado do app). `nil` com a sincronização
    /// desligada; só `MuralApp` o define.
    static var current: CloudSyncController?

    /// Quanto se espera, depois da última gravação de um mural, para enviar: gravações em sequência (digitação) viram um envio só.
    static let defaultSendDelay: Duration = .seconds(1)

    private let registry: BoardSessionRegistry
    private let delivery: BoardDelivery
    private let openSessions: OpenBoardSessions
    private let sendDelay: Duration
    @ObservationIgnored private var channels: [CloudDatabaseScope: Channel] = [:]
    /// O início, em andamento ou já feito: quem chama `start()` de novo espera esta mesma tarefa, e o que depende do início
    /// (`fetch`, `send`, `track`, `putInCloud`) também. `nil` até alguém ligar o controlador.
    @ObservationIgnored private var startTask: Task<Void, Never>?
    /// O fim da fila dos convites: cada leva espera a anterior, para duas não trocarem o `cloud` do mesmo mural ao mesmo tempo.
    @ObservationIgnored private var shareChain: Task<Void, Never>?
    /// O envio agendado de cada mural; uma nova gravação o cancela e agenda outro (a espera recomeça).
    @ObservationIgnored private var sendTasks: [BoardID: Task<Void, Never>] = [:]
    /// Os murais que esperam a primeira busca, como o último `refreshIssues` os leu dos coordenadores. A sessão que se abre depois
    /// recebe daqui.
    @ObservationIgnored private var awaitingFirstFetch = Set<BoardID>()
    /// A releitura agendada pelo aviso da ponte (`scheduleRefresh`), enquanto ela existe, e se chegou outro aviso durante ela.
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshAgain = false
    /// Quem avisa da interface de compartilhamento do sistema; só existe no modo `.cloudKit`.
    @ObservationIgnored private var sharingObserver: CKSystemSharingUIObserver?

    /// Há motores: a sincronização está ligada.
    var isEnabled: Bool { !channels.isEmpty }

    /// - Parameters:
    ///   - delivery: o roteamento das sessões de janela; a ponte junta e grava por ele, na fila serial das entregas.
    ///   - directory: onde ficam o estado de cada mural e o dos motores. O mesmo `SyncMetadataStore` serve aos dois bancos.
    ///   - cloud: o iCloud falso, que um teste divide com o "segundo Mac"; só vale com `.inMemory`.
    ///   - user: o nome do usuário no iCloud falso.
    ///   - sendDelay: a espera entre a última gravação de um mural e o envio; os testes a encurtam.
    init(
        mode: CloudSyncMode,
        registry: BoardSessionRegistry,
        delivery: BoardDelivery,
        directory: URL = LaunchConfiguration.libraryRoot().appendingPathComponent("Sync", isDirectory: true),
        cloud: InMemoryCloud = InMemoryCloud(),
        user: String = CloudSyncController.testUser,
        openSessions: OpenBoardSessions = .shared,
        sendDelay: Duration = CloudSyncController.defaultSendDelay
    ) {
        let effective: CloudSyncMode = mode == .cloudKit && !CloudAvailability.hasCloudKitEntitlement ? .off : mode
        self.mode = effective
        self.registry = registry
        self.delivery = delivery
        self.openSessions = openSessions
        self.sendDelay = sendDelay
        guard effective != .off else { return }

        let store = SyncMetadataStore(directory: directory)
        let container = effective == .cloudKit ? CKContainer(identifier: Self.containerIdentifier) : nil
        for scope in Self.scopes {
            // A ponte só guarda fechos fracos para o controlador: o coordenador a segura, e o controlador segura o coordenador.
            let bridge = CloudSyncBridge(
                scope: scope, registry: registry, delivery: delivery, openSessions: openSessions,
                notify: { [weak self] notice in self?.post(notice) },
                didApplyRemote: { [weak self] in self?.scheduleRefresh() })
            let coordinator = BoardSyncCoordinator(scope: scope, store: store, host: bridge)
            let engine: any CloudSyncEngine
            if let container {
                engine = CloudKitSyncEngine(container: container, scope: scope, coordinator: coordinator, store: store)
            } else {
                engine = InMemorySyncEngine(user: user, scope: scope, cloud: cloud, coordinator: coordinator)
            }
            channels[scope] = Channel(coordinator: coordinator, engine: engine)
        }
        if let container { observeSystemSharing(in: container) }

        // Toda sessão de janela, a que já existe e as que vierem, avisa o controlador de cada gravação local. A sessão não conhece
        // o controlador: só entrega o aviso a este fecho.
        openSessions.onRegister = { [weak self] session in self?.attach(session) }
        for session in openSessions.live { attach(session) }
    }

    // MARK: Ligar

    /// Liga os motores e entrega a cada um o que há por enviar dos murais já acompanhados (`pendingChanges(for:)`): o app pode ter
    /// sido fechado com gravações ainda não enviadas. Uma falha de um banco não impede o outro.
    ///
    /// O início é uma tarefa só: chamar de novo espera a mesma, e `fetch()`, `send()`, `track` e `putInCloud` esperam por ela antes de
    /// agir (o delegado do app busca ao ativar, às vezes antes de o início terminar). No fim, uma busca traz inteiras as zonas que a
    /// varredura dos motores adotou ao ligar (mural novo no iCloud, convite aceito em outro Mac).
    ///
    /// Com o iCloud falso (`.inMemory`), antes disso recria no iCloud falso a zona de cada mural privado acompanhado
    /// (`startZone` é idempotente). Com `-uiTestingKeep` o pacote e o estado de sincronização sobrevivem entre execuções, mas o
    /// iCloud falso nasce vazio a cada uma: sem a zona, a primeira busca a tomaria por apagada (`.zoneDeleted`), e o pacote do
    /// mural seria removido. O iCloud de verdade guarda as zonas, então não passa por aqui.
    func start() async {
        guard isEnabled else { return }
        if let startTask {
            await startTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performStart()
        }
        startTask = task
        await task.value
    }

    /// O corpo de `start()`. A busca do fim não espera `startTask` (seria esperar a si mesma): chama `performFetch()`.
    private func performStart() async {
        for scope in Self.scopes {
            guard let channel = channels[scope] else { continue }
            // Antes de ligar o motor, para nenhum convite de uma busca feita logo ao começar se perder.
            await channel.engine.setShareHandler { [weak self] shares in
                Task { @MainActor [weak self] in self?.receive(shares, scope: scope) }
            }
            do {
                try await channel.engine.start()
                let ids = try await channel.coordinator.boardIDs()
                if mode == .inMemory, scope == .private {
                    for id in ids { try await channel.engine.startZone(for: id) }
                }
                for id in ids {
                    try await channel.engine.add(try await channel.coordinator.pendingChanges(for: id))
                }
            } catch {
                Self.log.error("Banco \(scope.rawValue, privacy: .public) não ligado: \(String(describing: error), privacy: .public)")
            }
        }
        await refreshIssues()
        await performFetch()
    }

    /// Passa a acompanhar o mural: o coordenador guarda o estado (`startTracking`), o dono cria a zona no iCloud (só no banco
    /// privado) e o motor recebe o que há por enviar, que é enviado já. Quem chama grava antes o `cloud` no manifesto.
    /// - Throws: o que o coordenador ou o motor lançarem, como `BoardSyncCoordinatorError.wrongDatabase`.
    func track(_ id: BoardID, cloud: BoardCloudInfo) async throws {
        await startTask?.value
        let channel = try channel(for: cloud.database)
        if cloud.database == .private { try await channel.engine.startZone(for: id) }
        try await channel.engine.add(try await channel.coordinator.startTracking(id, cloud: cloud))
        try await channel.engine.send()
        await refreshIssues()
    }

    /// Põe um mural local no iCloud, do banco privado, como dono: cópia de segurança do pacote em `Backups/`, `cloud` no manifesto
    /// (pela sessão de janela, que o grava) e então `track`, que cria a zona e envia tudo.
    ///
    /// A cópia vem antes de qualquer mudança: é a rede de segurança para um primeiro envio que dê errado. Se o manifesto não
    /// grava, ou o mural não chega a ser acompanhado, o `cloud` volta a `nil`: mural com `cloud` e sem acompanhamento nunca
    /// sincronizaria, sem dizer nada.
    /// - Throws: `CloudSyncControllerError` para sincronização desligada, rascunho de exemplo ou mural que já tem `cloud`; ou o
    ///   que a biblioteca, a sessão ou o motor lançarem.
    func putInCloud(_ route: BoardRoute) async throws {
        guard isEnabled else { throw CloudSyncControllerError.disabled }
        guard case .saved(let id) = route else { throw CloudSyncControllerError.notASavedBoard }
        await startTask?.value
        let library = registry.library
        guard let snapshot = try await library.open(route) else { throw BoardLibraryError.unavailableRoute(route) }
        guard snapshot.manifest.cloud == nil else { throw CloudSyncControllerError.alreadyInCloud }

        _ = try await library.backupPackage(route, to: library.rootDirectory.appendingPathComponent("Backups", isDirectory: true))
        let cloud = BoardCloudInfo(
            database: .private, zoneName: CloudSchema.zoneName(for: id), zoneOwnerName: CloudZoneID.defaultOwnerName, permission: .owner)
        do {
            try await delivery.withSession(for: route) { session, _ in try await session.setCloud(cloud) }
        } catch {
            try? await delivery.withSession(for: route) { session, _ in try await session.setCloud(nil) }
            throw error
        }
        do {
            try await track(id, cloud: cloud)
        } catch {
            // Um `send` que falha depois de o mural ser acompanhado deixa tudo certo para a próxima tentativa; só o que nem chegou a
            // ser acompanhado volta a ser local.
            let scope = CloudDatabaseScope.private
            if let ids = try? await channels[scope]?.coordinator.boardIDs(), !ids.contains(id) {
                try? await delivery.withSession(for: route) { session, _ in try await session.setCloud(nil) }
            }
            throw error
        }
    }

    // MARK: Buscar e enviar

    /// Busca agora, nos dois bancos, o que mudou no iCloud. O que chega é junto e gravado pela ponte antes de cada busca voltar. Uma
    /// falha de rede ou do iCloud fica no registro do sistema e não impede o outro banco. Espera o início (`start()`), se ele estiver
    /// em andamento.
    func fetch() async {
        await startTask?.value
        await performFetch()
    }

    /// O corpo de `fetch()`, sem esperar o início: é também a busca do fim dele. Depois dos motores, espera a fila dos convites que a
    /// busca trouxe (a permissão do mural adotado vem deles) e relê os avisos.
    private func performFetch() async {
        for scope in Self.scopes {
            guard let channel = channels[scope] else { continue }
            do {
                try await channel.engine.fetch()
            } catch {
                Self.log.error("Busca no banco \(scope.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        await shareChain?.value
        await refreshIssues()
    }

    /// Envia agora, nos dois bancos, o que está pendente. Espera o início (`start()`), se ele estiver em andamento.
    func send() async {
        await startTask?.value
        for scope in Self.scopes {
            guard let channel = channels[scope] else { continue }
            do {
                try await channel.engine.send()
            } catch {
                Self.log.error("Envio no banco \(scope.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        await refreshIssues()
    }

    // MARK: Envio depois de gravar

    /// Passa a ouvir as gravações da sessão. Só gravações locais viram envio: uma junção (`fromRemote`) nunca o faz, porque quem
    /// calcula as pendências dela é o coordenador, com o estado novo já gravado (regra 3).
    ///
    /// O aviso roda dentro da gravação da sessão, às vezes dentro de `applyRemote`, de que o coordenador está esperando a volta.
    /// Por isso aqui só se agenda uma tarefa: nada espera o coordenador.
    ///
    /// A sessão nova também recebe, pela última leitura dos coordenadores (`awaitingFirstFetch`), se o mural ainda espera a primeira
    /// busca (abre só para ver).
    private func attach(_ session: BoardWindowSession) {
        let id = session.boardID
        session.onPersisted = { [weak self] _, fromRemote in
            guard !fromRemote else { return }
            self?.scheduleSend(for: id)
        }
        session.setAwaitingCloud(awaitingFirstFetch.contains(id))
    }

    /// Agenda o envio do mural para daqui a `sendDelay`; uma gravação nova antes disso cancela este e agenda outro.
    private func scheduleSend(for id: BoardID) {
        sendTasks[id]?.cancel()
        let delay = sendDelay
        sendTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.sendPending(for: id)
        }
    }

    /// Pede ao coordenador o que falta enviar do mural (lê o que está gravado, não a janela), entrega ao motor e envia. Mural que
    /// nenhum banco acompanha não tem pendência e não faz nada.
    private func sendPending(for id: BoardID) async {
        await startTask?.value
        for scope in Self.scopes {
            guard let channel = channels[scope] else { continue }
            do {
                let changes = try await channel.coordinator.pendingChanges(for: id)
                guard !changes.isEmpty else { continue }
                try await channel.engine.add(changes)
                try await channel.engine.send()
            } catch {
                Self.log.error(
                    "Envio do mural no banco \(scope.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        await refreshIssues()
    }

    // MARK: Avisos

    /// A pessoa já viu o aviso.
    func dismissNotice(_ id: UUID) {
        notices.removeAll { $0.id == id }
    }

    private func post(_ notice: CloudSyncNotice) {
        notices.append(notice)
        // O aviso é de um mural que deixou o iCloud neste Mac: o convite dele já não vale.
        if shareStates[notice.boardID] != nil { shareStates[notice.boardID] = nil }
    }

    // MARK: Convites

    /// Recebe os convites que uma busca trouxe. Voltam logo (o motor os entrega dentro do seu executor): o trabalho entra na fila,
    /// onde cada leva espera a anterior terminar.
    private func receive(_ shares: [ShareSummary], scope: CloudDatabaseScope) {
        let previous = shareChain
        shareChain = Task { [weak self] in
            await previous?.value
            await self?.apply(shares, scope: scope)
        }
    }

    /// Guarda cada convite em `shareStates` (o apagado sai) e, no banco compartilhado, passa ao mural o que o convite diz.
    ///
    /// Convite de mural que este banco não acompanha (recusado, ou que o motor não pôde adotar) não aparece em lugar nenhum e é
    /// ignorado. Não chama nada que espere o início (`track`, `fetch`): esta fila é esperada pela busca do fim dele.
    private func apply(_ shares: [ShareSummary], scope: CloudDatabaseScope) async {
        guard let channel = channels[scope] else { return }
        for share in shares {
            guard let id = CloudSchema.boardID(fromZoneName: share.zone.name) else { continue }
            if share.isDeleted {
                if shareStates[id] != nil { shareStates[id] = nil }
                continue
            }
            guard (try? await channel.coordinator.isTracking(id)) == true else { continue }
            if shareStates[id] != share { shareStates[id] = share }
            if scope == .shared { await adoptGrantedAccess(from: share, id: id, channel: channel) }
        }
        await refreshIssues()
    }

    /// No banco compartilhado, o convite diz o que esta pessoa pode fazer no mural e quem é o dono. O mural adotado começa só leitura
    /// e sem o nome do dono; quando o convite traz algo diferente do `cloud` do manifesto, o manifesto (pela sessão, que o grava,
    /// como `putInCloud`) e o coordenador (`startTracking`) passam a valer o novo, e o que estava pendente vai ao motor.
    ///
    /// Se o coordenador não aceita, o manifesto volta ao que era: o próximo convite tenta de novo, e os dois não ficam em desacordo.
    private func adoptGrantedAccess(from share: ShareSummary, id: BoardID, channel: Channel) async {
        let route = BoardRoute.saved(id)
        guard let current = (try? await registry.library.open(route))?.manifest.cloud, current.database == .shared else { return }
        var updated = current
        if let permission = share.currentUserPermission, permission != .owner { updated.permission = permission }
        if let owner = share.ownerDisplayName { updated.ownerDisplayName = owner }
        guard updated != current else { return }

        do {
            try await delivery.withSession(for: route) { session, _ in try await session.setCloud(updated) }
        } catch {
            Self.log.error("Convite não gravado no mural: \(String(describing: error), privacy: .public)")
            return
        }
        let pending: Set<PendingChange>
        do {
            pending = try await channel.coordinator.startTracking(id, cloud: updated)
        } catch {
            Self.log.error("Convite não aplicado ao coordenador: \(String(describing: error), privacy: .public)")
            try? await delivery.withSession(for: route) { session, _ in try await session.setCloud(current) }
            return
        }
        guard !pending.isEmpty else { return }
        do {
            try await channel.engine.add(pending)
            try await channel.engine.send()
        } catch {
            Self.log.error("Envio depois do convite: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Ações por papel

    /// O dono exclui o mural em todos os seus Macs: a zona sai do iCloud (e some para os convidados) e o pacote daqui vai para o
    /// Lixo, pelo caminho de "Excluir Mural". Nos outros Macs do dono e nos dos convidados, a busca que mostrar a zona apagada remove
    /// o pacote com um aviso.
    ///
    /// A zona é recusada e o mural deixa de ser acompanhado antes de a zona ser apagada: uma busca no meio, com a zona ainda no
    /// servidor, não a adota de novo (o pacote voltaria do Lixo), e o evento da zona apagada, que chega depois, não encontra o mural
    /// para remover. Cada passo pode ser repetido: se algo falhar no meio, tentar de novo termina o serviço.
    /// - Throws: `CloudSyncControllerError` (sincronização desligada, mural fora do iCloud ou que não é do dono) ou o que o
    ///   coordenador, o motor ou a biblioteca lançarem.
    func deleteEverywhere(_ id: BoardID) async throws {
        let (_, channel) = try await prepareAction(for: id, database: .private)
        try await stopSyncing(id, in: channel)
        try await channel.engine.deleteZone(for: id)
        try await trashPackage(of: id)
        await didLeave(id)
    }

    /// Quem recebeu o convite sai do mural compartilhado: o motor apaga o convite dela no iCloud (o dono e os outros convidados
    /// continuam com o mural) e o pacote daqui vai para o Lixo. Mesma ordem e mesma repetição segura de `deleteEverywhere`: enquanto o
    /// servidor não confirma, a busca que ainda mostrar a zona não a adota de novo.
    /// - Throws: `CloudSyncControllerError` (sincronização desligada, mural fora do iCloud ou que é do próprio dono) ou o que o
    ///   coordenador, o motor ou a biblioteca lançarem.
    func leaveShared(_ id: BoardID) async throws {
        let (cloud, channel) = try await prepareAction(for: id, database: .shared)
        try await stopSyncing(id, in: channel)
        try await channel.engine.leave(CloudZoneID(name: cloud.zoneName, ownerName: cloud.zoneOwnerName))
        try await trashPackage(of: id)
        await didLeave(id)
    }

    /// O dono tira o mural do iCloud: a zona é apagada (some para os convidados e para os outros Macs dele, onde a busca remove o
    /// pacote com um aviso) e o mural fica só neste Mac, sem `cloud` no manifesto. O `cloud` sai pela sessão, que o grava
    /// (`setCloud`), e por último: se a gravação falhar, o mural ainda mostra o iCloud e dá para tentar de novo.
    /// - Throws: como `deleteEverywhere`.
    func removeFromICloud(_ id: BoardID) async throws {
        let (_, channel) = try await prepareAction(for: id, database: .private)
        try await stopSyncing(id, in: channel)
        try await channel.engine.deleteZone(for: id)
        try await delivery.withSession(for: .saved(id)) { session, _ in try await session.setCloud(nil) }
        await didLeave(id)
    }

    /// Espera o início e confere o papel da pessoa no mural pelo `cloud` do manifesto, lido agora: o dono (banco privado) apaga a zona
    /// ou a tira do iCloud, e quem recebeu o convite (banco compartilhado) sai dele. Nada é tocado antes disto.
    private func prepareAction(
        for id: BoardID, database: BoardCloudInfo.Database
    ) async throws -> (cloud: BoardCloudInfo, channel: Channel) {
        guard isEnabled else { throw CloudSyncControllerError.disabled }
        await startTask?.value
        let route = BoardRoute.saved(id)
        guard let snapshot = try await registry.library.open(route) else { throw BoardLibraryError.unavailableRoute(route) }
        guard let cloud = snapshot.manifest.cloud else { throw CloudSyncControllerError.notInCloud }
        guard cloud.database == database else {
            throw database == .private ? CloudSyncControllerError.notOwner : CloudSyncControllerError.notGuest
        }
        return (cloud, try channel(for: database))
    }

    /// Para de acompanhar o mural neste Mac sem que uma busca o traga de volta: recusa a zona (até o servidor confirmar o apagamento)
    /// e esquece o estado, nesta ordem, porque a recusa lê o estado. O envio agendado do mural não tem mais o que enviar.
    private func stopSyncing(_ id: BoardID, in channel: Channel) async throws {
        sendTasks[id]?.cancel()
        sendTasks[id] = nil
        try await channel.coordinator.declineZone(of: id)
        try await channel.coordinator.stopTracking(id)
    }

    /// Fecha a aba (se aberta) e manda o pacote para o Lixo, pelo caminho de "Excluir Mural", na fila serial das entregas: não corre
    /// junto com uma junção ou uma colagem no mesmo mural. Pacote que já não existe é o que se queria.
    private func trashPackage(of id: BoardID) async throws {
        let route = BoardRoute.saved(id)
        let outcome: Result<Void, any Error> = await delivery.serially { [self] in
            do {
                if let tabs = delivery.tabs {
                    try await tabs.deleteBoard(route)
                } else {
                    await registry.close(id)
                    try await registry.library.deleteBoard(route)
                }
                return .success(())
            } catch BoardLibraryError.unavailableRoute {
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        try outcome.get()
    }

    /// O mural já não é acompanhado aqui: o convite dele sai de `shareStates` (depois dos que já estavam a caminho, para nenhum o
    /// devolver) e os avisos são relidos.
    private func didLeave(_ id: BoardID) async {
        await shareChain?.value
        if shareStates[id] != nil { shareStates[id] = nil }
        await refreshIssues()
    }

    // MARK: Compartilhamento do sistema

    /// A interface de compartilhamento do sistema grava e apaga o convite (`CKShare`) por conta própria, sem passar pelo motor: o
    /// observador avisa quando a pessoa para de compartilhar o mural (o mural continua no iCloud do dono) ou salva um convite. Os
    /// blocos rodam numa fila do observador, fora do Main Actor, e voltam por uma tarefa; o convite então segue o caminho dos que a
    /// busca traz (`receive`). Nos outros Macs, o convite apagado chega na busca (`ShareSummary.isDeleted`).
    private func observeSystemSharing(in container: CKContainer) {
        let observer = CKSystemSharingUIObserver(container: container)
        observer.systemSharingUIDidStopSharingBlock = { [weak self] recordID, result in
            let zone = CloudZoneID(recordID.zoneID)
            Task { @MainActor [weak self] in
                switch result {
                case .success:
                    self?.systemSharingDidStop(in: zone)
                case .failure(let error):
                    Self.log.error("Convite não apagado pelo sistema: \(String(describing: error), privacy: .public)")
                }
            }
        }
        observer.systemSharingUIDidSaveShareBlock = { [weak self] _, result in
            // O resumo sai do `CKShare` aqui, na fila do observador: só ele atravessa para o Main Actor.
            let summary = result.map { ShareSummary($0) }
            Task { @MainActor [weak self] in
                switch summary {
                case .success(let share):
                    self?.systemSharingDidSave(share)
                case .failure(let error):
                    Self.log.error("Convite não gravado pelo sistema: \(String(describing: error), privacy: .public)")
                }
            }
        }
        sharingObserver = observer
    }

    /// A pessoa parou de compartilhar o mural pela interface do sistema, que apagou o convite: ele sai de `shareStates`.
    func systemSharingDidStop(in zone: CloudZoneID) {
        receive([ShareSummary(zone: zone, isDeleted: true)], scope: Self.scope(of: zone))
    }

    /// A interface do sistema gravou o convite (alguém foi convidado, ou a permissão mudou): `shareStates` passa a ter o resumo dele.
    func systemSharingDidSave(_ share: ShareSummary) {
        receive([share], scope: Self.scope(of: share.zone))
    }

    /// O banco de uma zona pelo dono dela: a própria pessoa é o dono no privado; no compartilhado, outra.
    private static func scope(of zone: CloudZoneID) -> CloudDatabaseScope {
        zone.ownerName == CloudZoneID.defaultOwnerName ? .private : .shared
    }

    // MARK: Interno

    /// O coordenador de um banco, para quem precisa falar com ele direto (os testes, e a depuração da 5c).
    func coordinator(for scope: CloudDatabaseScope) -> BoardSyncCoordinator? {
        channels[scope]?.coordinator
    }

    private func channel(for database: BoardCloudInfo.Database) throws -> Channel {
        guard let scope = CloudDatabaseScope(rawValue: database.rawValue), let channel = channels[scope] else {
            throw CloudSyncControllerError.disabled
        }
        return channel
    }

    /// Lê de novo os avisos dos coordenadores, um por mural, e põe em só leitura as janelas dos murais que ainda esperam a primeira
    /// busca, tirando as que já a receberam.
    ///
    /// A espera vem da consulta própria dos coordenadores (`boardsAwaitingFirstFetch`), e não do aviso de maior prioridade: um
    /// `.localSaveFailed` esconderia `.awaitingFirstFetch`, e o mural continua sendo um pacote provisório. A consulta vem antes dos
    /// avisos porque espera o evento em andamento do coordenador: depois dela, o que ele gravou já vale também para `issues()`. Por
    /// isso este método nunca pode ser chamado, nem esperado, de dentro de um aviso do host (`applyRemote`), que roda durante um
    /// evento: o aviso da ponte só agenda `scheduleRefresh()`.
    private func refreshIssues() async {
        var awaiting = Set<BoardID>()
        var readAwaiting = true
        for scope in Self.scopes {
            guard let channel = channels[scope] else { continue }
            do {
                awaiting.formUnion(try await channel.coordinator.boardsAwaitingFirstFetch())
            } catch {
                // Sem a leitura, as janelas ficam como estão: um erro passageiro não deve liberar a edição de um pacote provisório.
                readAwaiting = false
                Self.log.error(
                    "Primeira busca no banco \(scope.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        var all: [BoardID: SyncIssue] = [:]
        for scope in Self.scopes {
            guard let channel = channels[scope] else { continue }
            all.merge(await channel.coordinator.issues()) { first, _ in first }
        }
        if all != issues { issues = all }
        guard readAwaiting else { return }
        awaitingFirstFetch = awaiting
        for session in openSessions.live { session.setAwaitingCloud(awaiting.contains(session.boardID)) }
    }

    /// Pede para reler os avisos depois de uma junção que o motor fez por conta própria, como a busca completa que o motor do CloudKit
    /// agenda ao adotar uma zona (o controlador não a provocou). Só agenda: o aviso da ponte chega durante um evento do coordenador, e
    /// a leitura espera esse evento terminar. Avisos seguidos (um por zona, um por lote) viram uma leitura só: com uma em andamento,
    /// apenas se marca que falta outra depois.
    private func scheduleRefresh() {
        guard refreshTask == nil else {
            refreshAgain = true
            return
        }
        refreshTask = Task { @MainActor [weak self] in
            while let self {
                self.refreshAgain = false
                await self.refreshIssues()
                guard self.refreshAgain else {
                    self.refreshTask = nil
                    return
                }
            }
        }
    }
}

enum CloudSyncControllerError: LocalizedError, Equatable {
    /// A sincronização está desligada (`CloudSyncMode.off`).
    case disabled
    /// Só mural salvo vai ao iCloud: o rascunho de exemplo ainda não é um mural da pessoa.
    case notASavedBoard
    /// O mural já tem `cloud` no manifesto (já está no iCloud, ou veio de um convite).
    case alreadyInCloud
    /// O mural não tem `cloud` no manifesto: não está no iCloud.
    case notInCloud
    /// A ação é do dono do mural (banco privado), e este é de outra pessoa.
    case notOwner
    /// A ação é de quem recebeu o convite (banco compartilhado), e este mural é do dono.
    case notGuest

    /// O texto que o alerta da janela mostra.
    var errorDescription: String? {
        switch self {
        case .disabled: "A sincronização com o iCloud está desligada neste Mac."
        case .notASavedBoard: "Salve o mural antes de pô-lo no iCloud."
        case .alreadyInCloud: "Este mural já está no iCloud."
        case .notInCloud: "Este mural não está no iCloud."
        case .notOwner: "Só quem criou o mural pode fazer isso."
        case .notGuest: "Este mural é seu, e não um convite recebido."
        }
    }
}
