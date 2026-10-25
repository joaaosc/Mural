import CloudKit
import Foundation
import MuralKit
import os

public enum CloudKitSyncEngineError: Error, Equatable, Sendable {
    /// `start()` ainda não foi chamado.
    case notStarted
    /// Só quem usa o banco privado cria e apaga zonas: o convidado recebe as do dono.
    case notOwner
}

/// O papel do `InMemorySyncEngine` com o iCloud de verdade: um `CKSyncEngine` por banco (privado ou compartilhado) que traduz os
/// eventos do CloudKit para chamadas do `BoardSyncCoordinator` e devolve ao motor as pendências que ele manda. Não decide nada: o que
/// enviar, como juntar e o que apagar estão no `SyncCore` e no coordenador; aqui só se convertem tipos (`CloudRecord+CloudKit`,
/// `CloudKitMapping`) e se encaminham eventos.
///
/// **Sem teste automático**: o `CKSyncEngine` não roda sem conta iCloud e container com o entitlement, e a tradução que se pode
/// testar sem eles está em `CloudKitMapping`, com testes. O comportamento real deste tipo (ordem dos eventos, o que o motor tira da
/// fila depois de uma recusa, aceitar convite, trocar de conta) só é conferido na Fase 0, com duas contas.
///
/// **Quem cria o container** é o app, depois de conferir que tem o entitlement de CloudKit: `CKContainer(identifier:)` sem ele encerra
/// o app. Nada aqui cria container, nem o `init`.
///
/// **Pendências**: depois de cada evento que passa pelo coordenador (`fetchedRecordZoneChanges`, `sentRecordZoneChanges`), as
/// pendências do motor nas zonas do evento são trocadas pelas que o coordenador devolveu, como faz o `InMemorySyncEngine`. Um
/// registro que o iCloud recusou por cota, permissão ou erro desconhecido não é reenviado na hora (seria um laço de recusas): volta na
/// próxima chamada de `add(_:)`, que o app faz com `BoardSyncCoordinator.pendingChanges(for:)` ao gravar o mural e ao abrir. Uma
/// falha passageira (sem rede, servidor ocupado) não é recusa: a pendência fica na fila e o motor tenta de novo.
///
/// **Arquivos que chegam**: o `fileURL` de um `CKAsset` buscado só vale durante o evento. O coordenador entrega a
/// `BoardSyncHost.applyRemote`, que copia para `Items/`, antes de `handleEvent` voltar; por isso nada é copiado aqui.
///
/// **Convites**: o `CKShare` da zona compartilhada chega junto dos registros, na busca e na busca completa. Ele não é parte do mural:
/// é separado antes de converter (senão o `SyncCore` o marcaria como ilegível e o mural ganharia um aviso falso) e vai a quem foi
/// ligado por `setShareHandler(_:)`, sem passar pelo coordenador.
///
/// **Regra da Apple**: `handleEvent` não chama `fetchChanges` nem `sendChanges`. Pendências novas entram por `state.add(...)`, que
/// agenda o envio sozinho; só `sendNow()` e `fetchNow()`, chamados de fora, forçam.
public actor CloudKitSyncEngine: CKSyncEngineDelegate {
    /// O tamanho máximo de um lote de envio. O CloudKit recusa pedido com registros demais; o motor chama
    /// `nextRecordZoneChangeBatch` de novo até a fila esvaziar.
    private static let maximumBatchSize = 100

    private let container: CKContainer
    private let scope: CloudDatabaseScope
    private let coordinator: BoardSyncCoordinator
    private let store: SyncMetadataStore
    private var syncEngine: CKSyncEngine?
    /// Quem recebe os convites que as buscas trazem; sem ninguém ligado, eles são descartados.
    private var shareHandler: (@Sendable ([ShareSummary]) -> Void)?

    /// - Parameters:
    ///   - container: o container do app (`iCloud.com.joaocosta.Mural`), já criado por quem confere o entitlement.
    ///   - scope: o banco deste motor; o coordenador deve ser o do mesmo banco.
    ///   - store: onde o estado do motor é guardado entre execuções (`engineState(for:)`).
    public init(container: CKContainer, scope: CloudDatabaseScope, coordinator: BoardSyncCoordinator, store: SyncMetadataStore) {
        self.container = container
        self.scope = scope
        self.coordinator = coordinator
        self.store = store
    }

    // MARK: Início

    /// Cria o `CKSyncEngine` do banco com o estado guardado da última execução. Estado ilegível não impede o começo: o motor parte do
    /// zero e busca tudo de novo, o que a junção do coordenador aceita sem efeito (valores iguais não mudam nada). Chamar de novo não
    /// faz nada.
    public func start() async throws {
        let data = try await store.engineState(for: scope)
        guard syncEngine == nil else { return }

        // Dados vazios são o estado apagado numa troca de conta (o `SyncMetadataStore` não tem como remover o arquivo).
        var serialization: CKSyncEngine.State.Serialization?
        if let data, !data.isEmpty {
            do {
                serialization = try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
            } catch {
                Logger.sync.error("Estado do motor ilegível no banco \(self.scope.rawValue, privacy: .public); recomeçando do zero")
            }
        }
        let database = scope == .private ? container.privateCloudDatabase : container.sharedCloudDatabase
        syncEngine = CKSyncEngine(CKSyncEngine.Configuration(database: database, stateSerialization: serialization, delegate: self))
    }

    // MARK: Entrada pública

    /// Liga quem recebe os convites (`CKShare`) que uma busca ou uma busca completa traz. O convite não é parte do mural, então não
    /// passa pelo coordenador: vai direto a quem mostra o compartilhamento. O handler roda no actor deste motor e deve voltar logo.
    public func setShareHandler(_ handler: @escaping @Sendable ([ShareSummary]) -> Void) {
        shareHandler = handler
    }

    /// Acrescenta pendências, como o app faz com o que `BoardSyncCoordinator.pendingChanges(for:)` devolve depois de gravar o mural.
    /// O motor agenda o envio sozinho.
    /// - Throws: `CloudKitSyncEngineError.notStarted` antes de `start()`.
    public func add(_ changes: Set<PendingChange>) throws {
        let engine = try requireEngine()
        let known = Set(engine.state.pendingRecordZoneChanges.compactMap { PendingChange($0) })
        let new = changes.subtracting(known)
        guard !new.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: new.map(\.engineChange))
    }

    /// Cria no iCloud a zona do mural. Só o dono, no banco privado: o convidado recebe a zona do dono.
    /// - Returns: a zona como o dono a vê.
    /// - Throws: `CloudKitSyncEngineError.notStarted` ou `.notOwner` (banco compartilhado).
    @discardableResult
    public func startZone(for boardID: BoardID) throws -> CloudZoneID {
        let engine = try requireEngine()
        guard scope == .private else { throw CloudKitSyncEngineError.notOwner }
        let zone = CloudZoneID(name: CloudSchema.zoneName(for: boardID))
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zone.ckZoneID))])
        return zone
    }

    /// Apaga do iCloud a zona do mural, com tudo o que há nela, e esquece o que o motor tinha para enviar a ela. Só o dono, no banco
    /// privado. Quem chama faz antes `BoardSyncCoordinator.stopTracking`: assim, quando a busca trouxer a zona apagada, o coordenador
    /// a ignora e o mural continua neste Mac, só local (nos outros Macs ele sai).
    /// - Throws: `CloudKitSyncEngineError.notStarted` ou `.notOwner` (banco compartilhado).
    public func deleteZone(for boardID: BoardID) throws {
        let engine = try requireEngine()
        guard scope == .private else { throw CloudKitSyncEngineError.notOwner }
        let zone = CloudZoneID(name: CloudSchema.zoneName(for: boardID))
        Self.replacePending(in: [zone], with: [], engine: engine)
        engine.state.add(pendingDatabaseChanges: [.deleteZone(zone.ckZoneID)])
    }

    /// Envia agora o que está pendente, sem esperar a agenda do motor. Fora de `handleEvent`, como a Apple pede.
    public func sendNow() async throws {
        try await requireEngine().sendChanges()
    }

    /// Busca agora o que mudou no iCloud, sem esperar a agenda do motor. Antes, busca inteira cada zona marcada para busca completa
    /// (`BoardSyncCoordinator.zonesNeedingFullFetch`: o app não conseguiu gravar o que chegou, e o motor já passou daquelas
    /// mudanças). Fora de `handleEvent`, como a Apple pede.
    public func fetchNow() async throws {
        let engine = try requireEngine()
        await fullFetchMarkedZones(engine: engine)
        try await engine.fetchChanges()
    }

    // MARK: CKSyncEngineDelegate

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            await saveEngineState(update.stateSerialization)
        case .accountChange(let change):
            await handleAccountChange(change.changeType)
        case .fetchedDatabaseChanges(let changes):
            await handleZoneDeletions(changes.deletions, engine: syncEngine)
            if !changes.modifications.isEmpty {
                // Zona nova no banco compartilhado (convite aceito) fica para a Fase 3.
                note("fetchedDatabaseChanges (zonas novas ou alteradas: \(changes.modifications.count))")
            }
        case .fetchedRecordZoneChanges(let changes):
            await handleFetched(changes, engine: syncEngine)
        case .sentRecordZoneChanges(let sent):
            await handleSent(sent, engine: syncEngine)
        case .sentDatabaseChanges(let sent):
            for failure in sent.failedZoneSaves {
                Logger.sync.error(
                    "Zona não criada: \(failure.zone.zoneID.zoneName, privacy: .public) (código \(failure.error.code.rawValue))")
            }
            for (zone, error) in sent.failedZoneDeletes {
                Logger.sync.error("Zona não apagada: \(zone.zoneName, privacy: .public) (código \(error.code.rawValue))")
            }
            note("sentDatabaseChanges")
        case .willFetchChanges: note("willFetchChanges")
        case .willFetchRecordZoneChanges(let fetch): note("willFetchRecordZoneChanges", zone: fetch.zoneID)
        case .didFetchRecordZoneChanges(let fetch):
            if let error = fetch.error {
                Logger.sync.error("Busca da zona \(fetch.zoneID.zoneName, privacy: .public) com erro (código \(error.code.rawValue))")
            } else {
                note("didFetchRecordZoneChanges", zone: fetch.zoneID)
            }
        case .didFetchChanges: note("didFetchChanges")
        case .willSendChanges: note("willSendChanges")
        case .didSendChanges: note("didSendChanges")
        @unknown default: note("evento desconhecido")
        }
    }

    /// O lote de envio: as pendências do escopo pedido, no máximo `maximumBatchSize`, em ordem fixa. Cada registro é pedido ao
    /// coordenador e convertido; o que ele não monta (`nil`, cartão grande demais ou erro) sai da fila do motor e fica de fora. A
    /// diferença com a base é a fila de verdade, então o que sai daqui volta quando o app chamar `add(_:)` de novo.
    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let requested = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges
            .filter { requested.contains($0) }
            .sorted(by: Self.isOrdered)
            .prefix(Self.maximumBatchSize)
        let coordinator = coordinator
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: Array(pending)) { recordID in
            await Self.record(for: recordID, coordinator: coordinator, engine: syncEngine)
        }
    }

    // MARK: Eventos

    private func saveEngineState(_ serialization: CKSyncEngine.State.Serialization) async {
        do {
            try await store.saveEngineState(try JSONEncoder().encode(serialization), for: scope)
        } catch {
            Logger.sync.error(
                "Estado do motor não gravado no banco \(self.scope.rawValue, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// `signOut` e `switchAccounts`: o que há aqui pertence a outra conta. Todos os murais deste banco saem com `.accountChanged` e o
    /// estado do motor é apagado (o motor já zera a fila). `signIn` só busca, o que o motor faz sozinho.
    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange.ChangeType) async {
        switch change {
        case .signIn:
            note("accountChange (entrou)")
        case .signOut, .switchAccounts:
            note("accountChange (saiu ou trocou)")
            await forgetEverything()
        @unknown default:
            note("accountChange desconhecido")
        }
    }

    private func forgetEverything() async {
        let boardIDs: [BoardID]
        do {
            boardIDs = try await store.boardIDs()
        } catch {
            Logger.sync.error("Murais não listados na troca de conta: \(String(describing: error), privacy: .public)")
            boardIDs = []
        }
        // O coordenador ignora o mural de outro banco, e um estado ilegível não impede os outros de saírem.
        for id in boardIDs {
            let zone = CloudZoneID(name: CloudSchema.zoneName(for: id))
            do {
                try await coordinator.handleZoneDeleted(zone, reason: .accountChanged)
            } catch {
                Logger.sync.error("Mural \(zone.name, privacy: .public) não removido: \(String(describing: error), privacy: .public)")
            }
        }
        do {
            try await store.saveEngineState(Data(), for: scope)
        } catch {
            Logger.sync.error("Estado do motor não apagado: \(String(describing: error), privacy: .public)")
        }
    }

    /// Zona apagada: no banco compartilhado, sempre acesso perdido; no privado, pelo motivo do CloudKit (`CloudKitMapping`). A fila
    /// do motor para a zona é esvaziada: ela já não existe.
    private func handleZoneDeletions(_ deletions: [CKDatabase.DatabaseChange.Deletion], engine: CKSyncEngine) async {
        for deletion in deletions {
            let zone = CloudZoneID(deletion.zoneID)
            let reason = CloudKitMapping.removalReason(for: deletion.reason, in: scope)
            Logger.sync.notice("Zona apagada: \(zone.name, privacy: .public) (\(String(describing: reason), privacy: .public))")
            Self.replacePending(in: [zone], with: [], engine: engine)
            do {
                try await coordinator.handleZoneDeleted(zone, reason: reason)
            } catch {
                Logger.sync.error("Zona \(zone.name, privacy: .public) não tratada: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func handleFetched(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges, engine: CKSyncEngine) async {
        let outcome = CloudKitMapping.fetchOutcome(
            modifications: changes.modifications.map(\.record),
            deletions: changes.deletions.map { (recordID: $0.recordID, recordType: $0.recordType) })
        if !outcome.saved.isEmpty || !outcome.deleted.isEmpty {
            do {
                let remaining = try await coordinator.handleFetched(saved: outcome.saved, deleted: outcome.deleted)
                Self.replacePending(in: outcome.zones, with: remaining, engine: engine)
            } catch {
                Logger.sync.error("Busca não tratada: \(String(describing: error), privacy: .public)")
            }
        }
        deliver(outcome.shares)
    }

    /// Entrega os convites de uma busca a quem os recebe, depois de o coordenador tratar os registros da mesma leva.
    private func deliver(_ shares: [ShareSummary]) {
        guard !shares.isEmpty else { return }
        shareHandler?(shares)
    }

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, engine: CKSyncEngine) async {
        let outcome = CloudKitMapping.sendOutcome(
            savedRecords: sent.savedRecords,
            failedSaves: sent.failedRecordSaves.map { ($0.record, $0.error) },
            deletedRecordIDs: sent.deletedRecordIDs,
            failedDeletes: sent.failedRecordDeletes)
        do {
            let remaining = try await coordinator.handleSent(saved: outcome.saved, deleted: outcome.deleted, failures: outcome.failures)
            let refused = outcome.refused
            Self.replacePending(in: outcome.zones, with: remaining.filter { !refused.contains($0.recordID) }, engine: engine)
            // Falha passageira: o motor tenta de novo; se ele a tirou da fila, ela volta.
            Self.keepPending(outcome.retriedByEngine, engine: engine)
        } catch {
            Logger.sync.error("Envio não tratado: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Busca completa

    private func fullFetchMarkedZones(engine: CKSyncEngine) async {
        let zones: [CloudZoneID]
        do {
            zones = try await coordinator.zonesNeedingFullFetch()
        } catch {
            Logger.sync.error("Zonas para busca completa não listadas: \(String(describing: error), privacy: .public)")
            return
        }
        for zone in zones {
            let scratch = FileManager.default.temporaryDirectory
                .appendingPathComponent("MuralFullFetch-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            do {
                let fetched = try await Self.allRecords(in: zone.ckZoneID, database: engine.database, copyingAssetsTo: scratch)
                let remaining = try await coordinator.handleFullFetch(zone, records: fetched.records)
                Self.replacePending(in: [zone], with: remaining, engine: engine)
                deliver(fetched.shares)
            } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
                Self.replacePending(in: [zone], with: [], engine: engine)
                do {
                    try await coordinator.handleZoneDeleted(zone, reason: scope == .private ? .zoneDeleted : .accessRevoked)
                } catch {
                    Logger.sync.error("Zona \(zone.name, privacy: .public) não tratada: \(String(describing: error), privacy: .public)")
                }
            } catch {
                // A marca continua: a próxima chamada de `fetchNow()` tenta de novo.
                Logger.sync.error(
                    "Busca completa da zona \(zone.name, privacy: .public) falhou: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Todos os registros que a zona tem agora: as mudanças desde o começo (`since: nil`), página a página. Um registro que falha ou
    /// não converte interrompe tudo (lança), porque na busca completa o que não vem conta como apagado. Os arquivos (`CKAsset`) são
    /// copiados para `directory` na hora: o arquivo do CloudKit pode sumir quando a operação termina.
    ///
    /// O convite da zona vem junto dos registros e é separado antes de converter (`CloudKitMapping.separatingShares`): como registro
    /// do mural ele não converteria, e a busca completa nunca terminaria.
    private static func allRecords(
        in zoneID: CKRecordZone.ID, database: CKDatabase, copyingAssetsTo directory: URL
    ) async throws -> (records: [CloudRecord], shares: [ShareSummary]) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var records: [CloudRecord] = []
        var shares: [ShareSummary] = []
        var token: CKServerChangeToken?
        var moreComing = true
        while moreComing {
            let page = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
            let (muralRecords, pageShares) = CloudKitMapping.separatingShares(
                from: try page.modificationResultsByID.values.map { try $0.get().record })
            shares.append(contentsOf: pageShares)
            for ckRecord in muralRecords {
                var record = try CloudRecord(ckRecord)
                for (key, value) in record.fields {
                    guard case .asset(let source) = value else { continue }
                    let copy = directory.appendingPathComponent(UUID().uuidString, isDirectory: false)
                    try FileManager.default.copyItem(at: source, to: copy)
                    record.fields[key] = .asset(copy)
                }
                records.append(record)
            }
            token = page.changeToken
            moreComing = page.moreComing
        }
        return (records, shares)
    }

    // MARK: Interno

    private func requireEngine() throws -> CKSyncEngine {
        guard let syncEngine else { throw CloudKitSyncEngineError.notStarted }
        return syncEngine
    }

    private func note(_ name: String, zone: CKRecordZone.ID? = nil) {
        if let zone {
            Logger.sync.debug(
                "Evento \(name, privacy: .public) (\(zone.zoneName, privacy: .public)) no banco \(self.scope.rawValue, privacy: .public)")
        } else {
            Logger.sync.debug("Evento \(name, privacy: .public) no banco \(self.scope.rawValue, privacy: .public)")
        }
    }

    /// Troca as pendências do motor nas `zones` pelas que o coordenador devolveu: tira as que não voltaram e põe as novas. Só mexe no
    /// que mudou, para não reiniciar o que o motor já tem agendado.
    private static func replacePending(in zones: Set<CloudZoneID>, with changes: Set<PendingChange>, engine: CKSyncEngine) {
        let current = Set(engine.state.pendingRecordZoneChanges.compactMap { PendingChange($0) })
        let currentInZones = current.filter { zones.contains($0.recordID.zone) }
        let stale = currentInZones.subtracting(changes)
        let new = changes.subtracting(current)
        if !stale.isEmpty { engine.state.remove(pendingRecordZoneChanges: stale.map(\.engineChange)) }
        if !new.isEmpty { engine.state.add(pendingRecordZoneChanges: new.map(\.engineChange)) }
    }

    /// Garante que as pendências estão na fila do motor, sem repetir as que já estão.
    private static func keepPending(_ changes: Set<PendingChange>, engine: CKSyncEngine) {
        let current = Set(engine.state.pendingRecordZoneChanges.compactMap { PendingChange($0) })
        let missing = changes.subtracting(current)
        if !missing.isEmpty { engine.state.add(pendingRecordZoneChanges: missing.map(\.engineChange)) }
    }

    /// O registro de uma pendência de gravação. Quando o coordenador não o monta, a pendência sai da fila do motor e o lote o ignora.
    private static func record(for recordID: CKRecord.ID, coordinator: BoardSyncCoordinator, engine: CKSyncEngine) async -> CKRecord? {
        do {
            if let record = try await coordinator.record(for: CloudRecordID(recordID)) { return try record.makeCKRecord() }
        } catch {
            // `recordTooLarge` já virou aviso do mural no coordenador.
            Logger.sync.error(
                "Registro não montado: \(recordID.recordName, privacy: .public) (\(String(describing: error), privacy: .public))")
        }
        engine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
        return nil
    }

    /// Ordem fixa: por zona, gravações antes de apagamentos e depois pelo nome do registro, como no `InMemorySyncEngine`.
    private static func isOrdered(_ lhs: CKSyncEngine.PendingRecordZoneChange, _ rhs: CKSyncEngine.PendingRecordZoneChange) -> Bool {
        key(of: lhs).lexicographicallyPrecedes(key(of: rhs))
    }

    private static func key(of change: CKSyncEngine.PendingRecordZoneChange) -> [String] {
        switch change {
        case .saveRecord(let id): [id.zoneID.ownerName, id.zoneID.zoneName, "0", id.recordName]
        case .deleteRecord(let id): [id.zoneID.ownerName, id.zoneID.zoneName, "1", id.recordName]
        @unknown default: ["", "", "2", ""]
        }
    }
}
