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
    /// As zonas do banco compartilhado adotadas cuja permissão real ainda não foi aplicada: isso acontece na primeira busca completa.
    private var zonesAwaitingPermission = Set<CloudZoneID>()
    /// O que este Mac ainda precisa enviar, como o `CKSyncEngine` o guarda: o coordenador diz o que é pendente, o motor decide quando
    /// enviar.
    public private(set) var pending = Set<PendingChange>()
    /// Quem recebe os convites que cada busca traz; sem ninguém ligado, eles são descartados, como no `CloudKitSyncEngine`.
    private var shareHandler: (@Sendable ([ShareSummary]) -> Void)?

    /// - Parameters:
    ///   - user: quem usa este Mac, o nome com que o iCloud falso o conhece.
    ///   - scope: o banco deste motor; o coordenador deve ser o do mesmo banco.
    public init(user: String, scope: CloudDatabaseScope, cloud: InMemoryCloud, coordinator: BoardSyncCoordinator) {
        self.user = user
        self.scope = scope
        self.cloud = cloud
        self.coordinator = coordinator
    }

    /// Liga quem recebe os convites, como `CloudKitSyncEngine.setShareHandler(_:)`. Depois de cada `fetchChanges()` o fecho recebe um
    /// `ShareSummary` por zona que esta pessoa vê (veja `fetchChanges()`). Roda no executor do motor e deve voltar logo.
    public func setShareHandler(_ handler: @escaping @Sendable ([ShareSummary]) -> Void) {
        shareHandler = handler
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

    /// Apaga do iCloud a zona do mural, com tudo o que há nela, para o dono e para quem a recebeu, e esquece o que este motor tinha
    /// para enviar a ela. Só o dono, no banco privado. Quem chama faz antes `BoardSyncCoordinator.declineZone(of:)` e `stopTracking`,
    /// como com o `CloudKitSyncEngine`: assim a busca que mostrar a zona apagada não tira o pacote daqui.
    /// - Throws: `InMemorySyncEngineError.notOwner` no banco compartilhado.
    public func deleteZone(for boardID: BoardID) async throws {
        guard scope == .private else { throw InMemorySyncEngineError.notOwner }
        let zone = CloudZoneID(name: CloudSchema.zoneName(for: boardID))
        await cloud.deleteZone(zone.name, owner: user)
        forget(zone)
    }

    /// O convidado deixa o mural: revoga o próprio acesso no iCloud, e a zona some para ele, sem afetar o dono. Quem chama faz antes
    /// `declineZone(of:)` e `stopTracking`. Só vale no banco compartilhado; sair de uma zona que já não existe não é erro.
    public func leaveZone(_ zone: CloudZoneID) async {
        guard scope == .shared else { return }
        try? await cloud.revoke(zone: zone.name, owner: zone.ownerName, from: user)
        forget(zone)
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
    ///
    /// **Zonas novas**: antes da busca, a zona que esta pessoa vê e o coordenador não acompanha nem recusou é adotada
    /// (`BoardSyncCoordinator.adoptZone`), como o motor de verdade fará com a zona nova que o CloudKit mostra. Ela entra na busca
    /// completa, por esperar a primeira busca. No banco compartilhado a adoção parte de só leitura (no CloudKit a permissão só chega
    /// com o convite) e, depois da primeira busca, passa a ser a que o iCloud falso deu à pessoa. Zona recusada (`declinedZones()`)
    /// fica fora da busca, e a recusa de uma zona que já não existe é desfeita (`handleZoneDeleted`): o servidor confirmou o apagamento.
    ///
    /// **Convites**: no fim, com `setShareHandler(_:)` ligado, entrega o convite de cada zona que esta pessoa vê (`deliverShares`).
    public func fetchChanges() async throws {
        let visible = await cloud.zones(for: user, scope: scope)
        let declined = try await coordinator.declinedZones()
        try await confirmGoneDeclinedZones(declined, visible: visible)
        try await adoptNewZones(among: visible, declined: declined)

        let declinedNames = Set(declined.map(\.name))
        let tracked = Set(try await coordinator.boardIDs())
        let fullFetch = Set(try await coordinator.zonesNeedingFullFetch().map(\.name))
        var zones = Set(tokens.keys)
        for zone in visible {
            if let id = CloudSchema.boardID(fromZoneName: zone.name), tracked.contains(id) { zones.insert(zone) }
        }

        for zone in zones.sorted(by: { ($0.ownerName, $0.name) < ($1.ownerName, $1.name) }) {
            guard let id = CloudSchema.boardID(fromZoneName: zone.name), tracked.contains(id), !declinedNames.contains(zone.name) else {
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
                try await applyGrantedPermission(for: zone, id: id)
            } else if !changes.saved.isEmpty || !changes.deleted.isEmpty {
                let remaining = try await coordinator.handleFetched(saved: changes.saved, deleted: changes.deleted)
                // O coordenador calcula as pendências do mural com o estado novo: vale o que ele disse.
                pending = pending.filter { $0.recordID.zone != zone }.union(remaining)
            }
            tokens[zone] = changes.token
        }
        await deliverShares(for: visible)
    }

    // MARK: Interno

    private func forget(_ zone: CloudZoneID) {
        tokens[zone] = nil
        pending = pending.filter { $0.recordID.zone != zone }
        zonesAwaitingPermission.remove(zone)
    }

    /// Adota as zonas que esta pessoa vê e o coordenador não acompanha nem recusou. Um host que não cria pacotes de murais do iCloud
    /// (`BoardSyncAdoptionError.unsupported`) deixa a zona sem acompanhar, como era antes da adoção; as outras respostas (conflito de
    /// id, por exemplo) também a deixam de fora.
    private func adoptNewZones(among visible: [CloudZoneID], declined: Set<CloudZoneID>) async throws {
        let declinedNames = Set(declined.map(\.name))
        let tracked = Set(try await coordinator.boardIDs())
        for zone in visible {
            guard let id = CloudSchema.boardID(fromZoneName: zone.name), !tracked.contains(id), !declinedNames.contains(zone.name) else {
                continue
            }
            do {
                let result = try await coordinator.adoptZone(zone, cloud: adoptionInfo(for: zone), name: nil)
                if result == .adopted && scope == .shared { zonesAwaitingPermission.insert(zone) }
            } catch BoardSyncAdoptionError.unsupported {
                continue
            }
        }
    }

    /// Onde o mural adotado vive e o que esta pessoa pode fazer nele até a primeira busca: no banco privado ela é a dona; no
    /// compartilhado a permissão só chegaria com o convite, então vale o menos que se pode dar.
    private func adoptionInfo(for zone: CloudZoneID) -> BoardCloudInfo {
        switch scope {
        case .private:
            BoardCloudInfo(database: .private, zoneName: zone.name, zoneOwnerName: zone.ownerName, permission: .owner)
        case .shared:
            BoardCloudInfo(database: .shared, zoneName: zone.name, zoneOwnerName: zone.ownerName, permission: .readOnly)
        }
    }

    /// Depois da primeira busca de uma zona adotada no banco compartilhado, passa a valer a permissão que o iCloud falso deu a esta
    /// pessoa (`InMemoryCloud.guestPermission`), pelo mesmo caminho que o app usa: `startTracking` com a permissão nova.
    private func applyGrantedPermission(for zone: CloudZoneID, id: BoardID) async throws {
        guard zonesAwaitingPermission.contains(zone),
            let granted = await cloud.guestPermission(of: user, inZone: zone.name, owner: zone.ownerName)
        else { return }
        let info = BoardCloudInfo(
            database: .shared, zoneName: zone.name, zoneOwnerName: zone.ownerName, permission: Self.permission(of: granted))
        let resumed = try await coordinator.startTracking(id, cloud: info)
        pending = pending.filter { $0.recordID.zone != zone }.union(resumed)
        zonesAwaitingPermission.remove(zone)
    }

    private static func permission(of guest: InMemoryCloud.GuestPermission) -> BoardCloudInfo.Permission {
        guest == .readWrite ? .readWrite : .readOnly
    }

    /// Um convite por zona que esta pessoa vê, como o `CKShare` que a busca do CloudKit traz junto dos registros:
    /// - no banco compartilhado, a permissão que o dono deu a ela, o nome do dono no iCloud falso (também o `ownerUserRecordName`) e
    ///   todos os convidados da zona como participantes (todos aceitos): é por essa lista que o convidado confere as outras pessoas
    ///   do Live Share;
    /// - no privado, `.owner`, ele mesmo como dono (`ownerUserRecordName`) e os convidados como participantes (todos aceitos);
    /// - no privado, a zona sem nenhum convidado sai como apagada: no CloudKit, parar de compartilhar apaga o convite.
    private func deliverShares(for visible: [CloudZoneID]) async {
        guard let shareHandler else { return }
        var shares: [ShareSummary] = []
        for zone in visible {
            switch scope {
            case .private:
                let guests = await cloud.guests(inZone: zone.name, owner: user)
                guard !guests.isEmpty else {
                    shares.append(ShareSummary(zone: zone, isDeleted: true))
                    continue
                }
                shares.append(
                    ShareSummary(
                        zone: zone, currentUserPermission: .owner, ownerDisplayName: user, ownerUserRecordName: user,
                        participants: Self.participants(of: guests)))
            case .shared:
                guard let granted = await cloud.guestPermission(of: user, inZone: zone.name, owner: zone.ownerName) else { continue }
                let guests = await cloud.guests(inZone: zone.name, owner: zone.ownerName)
                shares.append(
                    ShareSummary(
                        zone: zone, currentUserPermission: Self.permission(of: granted), ownerDisplayName: zone.ownerName,
                        ownerUserRecordName: zone.ownerName, participants: Self.participants(of: guests)))
            }
        }
        guard !shares.isEmpty else { return }
        shareHandler(shares)
    }

    /// Os convidados do iCloud falso como o convite os lista: ordenados pelo nome, todos aceitos.
    private static func participants(of guests: [String: InMemoryCloud.GuestPermission]) -> [ShareSummary.Participant] {
        guests.sorted { $0.key < $1.key }.map {
            ShareSummary.Participant(
                displayName: $0.key, userRecordName: $0.key, permission: permission(of: $0.value), isAccepted: true)
        }
    }

    /// A recusa de uma zona que esta pessoa já não vê foi confirmada pelo servidor: a zona foi apagada, ou o acesso acabou.
    private func confirmGoneDeclinedZones(_ declined: Set<CloudZoneID>, visible: [CloudZoneID]) async throws {
        let visibleNames = Set(visible.map(\.name))
        for zone in declined.sorted(by: { ($0.ownerName, $0.name) < ($1.ownerName, $1.name) }) where !visibleNames.contains(zone.name) {
            forget(zone)
            try await coordinator.handleZoneDeleted(zone, reason: scope == .private ? .zoneDeleted : .accessRevoked)
        }
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
