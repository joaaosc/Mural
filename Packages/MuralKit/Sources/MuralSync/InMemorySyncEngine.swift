import Foundation
import MuralKit

public enum InMemorySyncEngineError: Error, Equatable, Sendable {
    /// Só quem usa o banco privado cria zonas: o convidado recebe as do dono.
    case notOwner
    /// O envio continuou mudando de estado depois de muitas passadas: algo se repete sem fim.
    case sendDidNotSettle
}

/// O papel do `CKSyncEngine` para um Mac e um banco, ligado ao `InMemoryCloud`: guarda o que está pendente, envia, busca e entrega o
/// resultado ao `BoardSyncCoordinator`. É o motor dos testes e fica público porque os testes de interface do app o usam.
///
/// Não tem agenda: quem chama decide quando enviar (`sendChanges()`) e quando buscar (`fetchChanges()`), o que deixa os testes
/// escolherem a ordem em que dois Macs se encontram, inclusive com um só deles enviando ou buscando.
public actor InMemorySyncEngine {
    /// Quantas passadas de envio, no máximo, numa chamada de `sendChanges()`.
    private static let maximumSendPasses = 50

    private let user: String
    private let scope: CloudDatabaseScope
    private let cloud: InMemoryCloud
    private let coordinator: BoardSyncCoordinator

    /// O contador de cada zona conhecida, para a próxima busca trazer só o que mudou.
    private var tokens: [CloudZoneID: Int] = [:]
    /// O que este Mac ainda precisa enviar, como o `CKSyncEngine` o guarda: o coordenador diz o que é pendente, o motor decide quando
    /// enviar.
    public private(set) var pending = Set<PendingChange>()

    /// - Parameters:
    ///   - user: quem usa este Mac, o nome com que o iCloud falso o conhece.
    ///   - scope: o banco deste motor; o coordenador deve ser o do mesmo banco.
    public init(user: String, scope: CloudDatabaseScope, cloud: InMemoryCloud, coordinator: BoardSyncCoordinator) {
        self.user = user
        self.scope = scope
        self.cloud = cloud
        self.coordinator = coordinator
    }

    /// Acrescenta pendências, como o app faz com o que `BoardSyncCoordinator.pendingChanges(for:)` devolve depois de gravar o mural.
    public func add(_ changes: Set<PendingChange>) {
        pending.formUnion(changes)
    }

    /// Cria no iCloud a zona do mural. Só o dono, no banco privado.
    /// - Returns: a zona como o dono a vê.
    /// - Throws: `InMemorySyncEngineError.notOwner` no banco compartilhado.
    @discardableResult
    public func startZone(for boardID: BoardID) async throws -> CloudZoneID {
        guard scope == .private else { throw InMemorySyncEngineError.notOwner }
        let zone = CloudZoneID(name: CloudSchema.zoneName(for: boardID))
        await cloud.createZone(zone.name, owner: user)
        tokens[zone] = tokens[zone] ?? 0
        return zone
    }

    // MARK: Enviar

    /// Envia o que está pendente: pede cada registro ao coordenador, grava no iCloud, entrega o resultado a `handleSent` e repete
    /// com o que voltar pendente, até esvaziar ou o conjunto não mudar mais (uma recusa que se repete deixa a pendência para a
    /// próxima chamada). Pendência cujo registro o coordenador não monta (`nil`, ou cartão grande demais) sai do conjunto.
    /// - Returns: quantas vezes o iCloud foi chamado.
    /// - Throws: `InMemorySyncEngineError.sendDidNotSettle` se o conjunto não para de mudar.
    @discardableResult
    public func sendChanges() async throws -> Int {
        var passes = 0
        for _ in 0..<Self.maximumSendPasses {
            guard !pending.isEmpty else { return passes }
            let before = pending
            if try await sendOnce() { passes += 1 }
            if pending == before { return passes }
        }
        throw InMemorySyncEngineError.sendDidNotSettle
    }

    /// Uma passada: monta os registros, envia e entrega o resultado. `false` se não havia nada a enviar.
    private func sendOnce() async throws -> Bool {
        let attempted = pending.sorted(by: Self.isOrdered)
        var records: [CloudRecord] = []
        var deletions: [CloudRecordID] = []
        var dropped = Set<PendingChange>()
        for change in attempted {
            switch change {
            case .save(let id):
                do {
                    if let record = try await coordinator.record(for: id) {
                        records.append(record)
                    } else {
                        dropped.insert(change)
                    }
                } catch CardRecordMappingError.recordTooLarge {
                    dropped.insert(change)
                }
            case .delete(let id):
                deletions.append(id)
            }
        }
        pending.subtract(dropped)
        guard !records.isEmpty || !deletions.isEmpty else { return false }

        let result = await cloud.send(saving: records, deleting: deletions, as: user)
        var zones = Set(result.saved.map(\.id.zone))
        zones.formUnion(result.deleted.map(\.zone))
        zones.formUnion(result.failures.map(\.zone))
        let remaining = try await coordinator.handleSent(saved: result.saved, deleted: result.deleted, failures: result.failures)
        // O coordenador devolve o que continua pendente dos murais do envio: vale o que ele disse, no lugar do que foi tentado.
        pending.subtract(attempted.filter { zones.contains($0.recordID.zone) })
        pending.formUnion(remaining)
        return true
    }

    // MARK: Buscar

    /// Busca em cada zona conhecida o que mudou desde o contador dela e entrega a `handleFetched`. São as zonas dos murais que o
    /// coordenador acompanha (no banco privado, as do dono; no compartilhado, as que outras pessoas deram a esta) e as que já foram
    /// buscadas. Zona que sumiu vira `handleZoneDeleted`: `.zoneDeleted` se foi apagada e `.accessRevoked` se só o convite acabou.
    /// Zona de mural marcado para busca completa (`zonesNeedingFullFetch`) é buscada inteira, desde o começo, e vai a
    /// `handleFullFetch`.
    public func fetchChanges() async throws {
        let tracked = Set(try await coordinator.boardIDs())
        let fullFetch = Set(try await coordinator.zonesNeedingFullFetch().map(\.name))
        var zones = Set(tokens.keys)
        for zone in await cloud.zones(for: user, scope: scope) {
            if let id = CloudSchema.boardID(fromZoneName: zone.name), tracked.contains(id) { zones.insert(zone) }
        }

        for zone in zones.sorted(by: { ($0.ownerName, $0.name) < ($1.ownerName, $1.name) }) {
            guard let id = CloudSchema.boardID(fromZoneName: zone.name), tracked.contains(id) else {
                forget(zone)
                continue
            }
            let isFull = fullFetch.contains(zone.name)
            let changes: InMemoryCloud.FetchedChanges
            do {
                changes = try await cloud.fetchChanges(zone: zone, since: isFull ? 0 : tokens[zone] ?? 0, as: user)
            } catch InMemoryCloudError.zoneDeleted {
                forget(zone)
                try await coordinator.handleZoneDeleted(zone, reason: .zoneDeleted)
                continue
            } catch InMemoryCloudError.accessRevoked {
                forget(zone)
                try await coordinator.handleZoneDeleted(zone, reason: .accessRevoked)
                continue
            }
            if isFull {
                // Desde o começo, os registros mudados são todos os que a zona tem agora.
                let remaining = try await coordinator.handleFullFetch(zone, records: changes.saved)
                pending = pending.filter { $0.recordID.zone != zone }.union(remaining)
            } else if !changes.saved.isEmpty || !changes.deleted.isEmpty {
                let remaining = try await coordinator.handleFetched(saved: changes.saved, deleted: changes.deleted)
                // O coordenador calcula as pendências do mural com o estado novo: vale o que ele disse.
                pending = pending.filter { $0.recordID.zone != zone }.union(remaining)
            }
            tokens[zone] = changes.token
        }
    }

    // MARK: Interno

    private func forget(_ zone: CloudZoneID) {
        tokens[zone] = nil
        pending = pending.filter { $0.recordID.zone != zone }
    }

    /// Ordem fixa: por zona, gravações antes de apagamentos e depois pelo nome do registro.
    private static func isOrdered(_ lhs: PendingChange, _ rhs: PendingChange) -> Bool {
        key(of: lhs).lexicographicallyPrecedes(key(of: rhs))
    }

    private static func key(of change: PendingChange) -> [String] {
        switch change {
        case .save(let id): [id.zone.ownerName, id.zone.name, "0", id.name]
        case .delete(let id): [id.zone.ownerName, id.zone.name, "1", id.name]
        }
    }
}
