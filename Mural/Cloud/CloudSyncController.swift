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
    @ObservationIgnored private var isStarted = false
    /// O envio agendado de cada mural; uma nova gravação o cancela e agenda outro (a espera recomeça).
    @ObservationIgnored private var sendTasks: [BoardID: Task<Void, Never>] = [:]

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
            // A ponte só guarda um fecho fraco para o controlador: o coordenador a segura, e o controlador segura o coordenador.
            let bridge = CloudSyncBridge(scope: scope, registry: registry, delivery: delivery, openSessions: openSessions) {
                [weak self] notice in self?.post(notice)
            }
            let coordinator = BoardSyncCoordinator(scope: scope, store: store, host: bridge)
            let engine: any CloudSyncEngine
            if let container {
                engine = CloudKitSyncEngine(container: container, scope: scope, coordinator: coordinator, store: store)
            } else {
                engine = InMemorySyncEngine(user: user, scope: scope, cloud: cloud, coordinator: coordinator)
            }
            channels[scope] = Channel(coordinator: coordinator, engine: engine)
        }

        // Toda sessão de janela, a que já existe e as que vierem, avisa o controlador de cada gravação local. A sessão não conhece
        // o controlador: só entrega o aviso a este fecho.
        openSessions.onRegister = { [weak self] session in self?.attach(session) }
        for session in openSessions.live { attach(session) }
    }

    // MARK: Ligar

    /// Liga os motores e entrega a cada um o que há por enviar dos murais já acompanhados (`pendingChanges(for:)`): o app pode ter
    /// sido fechado com gravações ainda não enviadas. Chamar de novo não faz nada. Uma falha de um banco não impede o outro.
    ///
    /// Com o iCloud falso (`.inMemory`), antes disso recria no iCloud falso a zona de cada mural privado acompanhado
    /// (`startZone` é idempotente). Com `-uiTestingKeep` o pacote e o estado de sincronização sobrevivem entre execuções, mas o
    /// iCloud falso nasce vazio a cada uma: sem a zona, a primeira busca a tomaria por apagada (`.zoneDeleted`), e o pacote do
    /// mural seria removido. O iCloud de verdade guarda as zonas, então não passa por aqui.
    func start() async {
        guard isEnabled, !isStarted else { return }
        isStarted = true
        for scope in Self.scopes {
            guard let channel = channels[scope] else { continue }
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
    }

    /// Passa a acompanhar o mural: o coordenador guarda o estado (`startTracking`), o dono cria a zona no iCloud (só no banco
    /// privado) e o motor recebe o que há por enviar, que é enviado já. Quem chama grava antes o `cloud` no manifesto.
    /// - Throws: o que o coordenador ou o motor lançarem, como `BoardSyncCoordinatorError.wrongDatabase`.
    func track(_ id: BoardID, cloud: BoardCloudInfo) async throws {
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
    /// falha de rede ou do iCloud fica no registro do sistema e não impede o outro banco.
    func fetch() async {
        for scope in Self.scopes {
            guard let channel = channels[scope] else { continue }
            do {
                try await channel.engine.fetch()
            } catch {
                Self.log.error("Busca no banco \(scope.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        await refreshIssues()
    }

    /// Envia agora, nos dois bancos, o que está pendente.
    func send() async {
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
    private func attach(_ session: BoardWindowSession) {
        let id = session.boardID
        session.onPersisted = { [weak self] _, fromRemote in
            guard !fromRemote else { return }
            self?.scheduleSend(for: id)
        }
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

    /// Lê de novo os avisos dos coordenadores, um por mural.
    private func refreshIssues() async {
        var all: [BoardID: SyncIssue] = [:]
        for scope in Self.scopes {
            guard let channel = channels[scope] else { continue }
            all.merge(await channel.coordinator.issues()) { first, _ in first }
        }
        if all != issues { issues = all }
    }
}

enum CloudSyncControllerError: LocalizedError, Equatable {
    /// A sincronização está desligada (`CloudSyncMode.off`).
    case disabled
    /// Só mural salvo vai ao iCloud: o rascunho de exemplo ainda não é um mural da pessoa.
    case notASavedBoard
    /// O mural já tem `cloud` no manifesto (já está no iCloud, ou veio de um convite).
    case alreadyInCloud

    /// O texto que o alerta da janela mostra.
    var errorDescription: String? {
        switch self {
        case .disabled: "A sincronização com o iCloud está desligada neste Mac."
        case .notASavedBoard: "Salve o mural antes de pô-lo no iCloud."
        case .alreadyInCloud: "Este mural já está no iCloud."
        }
    }
}
