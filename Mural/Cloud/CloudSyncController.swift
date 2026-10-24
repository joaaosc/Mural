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

    @ObservationIgnored private var channels: [CloudDatabaseScope: Channel] = [:]
    @ObservationIgnored private var isStarted = false

    /// Há motores: a sincronização está ligada.
    var isEnabled: Bool { !channels.isEmpty }

    /// - Parameters:
    ///   - delivery: o roteamento das sessões de janela; a ponte junta e grava por ele, na fila serial das entregas.
    ///   - directory: onde ficam o estado de cada mural e o dos motores. O mesmo `SyncMetadataStore` serve aos dois bancos.
    ///   - cloud: o iCloud falso, que um teste divide com o "segundo Mac"; só vale com `.inMemory`.
    ///   - user: o nome do usuário no iCloud falso.
    init(
        mode: CloudSyncMode,
        registry: BoardSessionRegistry,
        delivery: BoardDelivery,
        directory: URL = LaunchConfiguration.libraryRoot().appendingPathComponent("Sync", isDirectory: true),
        cloud: InMemoryCloud = InMemoryCloud(),
        user: String = CloudSyncController.testUser,
        openSessions: OpenBoardSessions = .shared
    ) {
        let effective: CloudSyncMode = mode == .cloudKit && !CloudAvailability.hasCloudKitEntitlement ? .off : mode
        self.mode = effective
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
    }

    // MARK: Ligar

    /// Liga os motores e entrega a cada um o que há por enviar dos murais já acompanhados (`pendingChanges(for:)`): o app pode ter
    /// sido fechado com gravações ainda não enviadas. Chamar de novo não faz nada. Uma falha de um banco não impede o outro.
    func start() async {
        guard isEnabled, !isStarted else { return }
        isStarted = true
        for scope in Self.scopes {
            guard let channel = channels[scope] else { continue }
            do {
                try await channel.engine.start()
                for id in try await channel.coordinator.boardIDs() {
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

enum CloudSyncControllerError: Error, Equatable {
    /// A sincronização está desligada (`CloudSyncMode.off`).
    case disabled
}
