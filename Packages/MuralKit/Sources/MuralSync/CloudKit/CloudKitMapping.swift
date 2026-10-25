import CloudKit
import Foundation
import MuralKit
import os

extension Logger {
    /// O registro do motor de sincronização. Só vão para ele o nome do mural (da zona), o nome do registro, o tipo do evento e o
    /// código do erro; nunca o conteúdo de um cartão.
    static let sync = Logger(subsystem: "com.joaocosta.Mural", category: "Sincronização")
}

/// O convite de um mural (o `CKShare` da zona) sem tipos do CloudKit: o endereço, quem foi convidado e o que esta pessoa pode fazer.
/// O CloudKit grava o convite como um registro dentro da zona compartilhada, mas ele não é parte do mural: nunca segue para a junção
/// (`SyncCore`), só para quem mostra e gerencia o compartilhamento.
public struct ShareSummary: Equatable, Sendable {
    /// Uma pessoa convidada. O dono do mural não entra na lista.
    public struct Participant: Equatable, Sendable {
        /// O nome para mostrar; `nil` quando o iCloud não o deu (quem não está nos contatos pode vir sem nome).
        public var displayName: String?
        /// O nome do registro de usuário no CloudKit, que identifica a pessoa.
        public var userRecordName: String?
        public var permission: BoardCloudInfo.Permission
        /// Só depois de aceitar o convite a pessoa tem acesso; antes é um convite pendente.
        public var isAccepted: Bool

        public init(displayName: String? = nil, userRecordName: String? = nil, permission: BoardCloudInfo.Permission, isAccepted: Bool) {
            self.displayName = displayName
            self.userRecordName = userRecordName
            self.permission = permission
            self.isAccepted = isAccepted
        }
    }

    /// A zona do mural, como este Mac a vê (o convite mora nela).
    public var zone: CloudZoneID
    public var title: String?
    public var url: URL?
    /// O que esta pessoa pode fazer no mural; `nil` quando o convite não a lista ou o CloudKit não disse.
    public var currentUserPermission: BoardCloudInfo.Permission?
    public var ownerDisplayName: String?
    public var participants: [Participant]
    /// O convite foi apagado: o dono parou de compartilhar o mural. Os outros campos ficam vazios.
    public var isDeleted: Bool

    public init(
        zone: CloudZoneID,
        title: String? = nil,
        url: URL? = nil,
        currentUserPermission: BoardCloudInfo.Permission? = nil,
        ownerDisplayName: String? = nil,
        participants: [Participant] = [],
        isDeleted: Bool = false
    ) {
        self.zone = zone
        self.title = title
        self.url = url
        self.currentUserPermission = currentUserPermission
        self.ownerDisplayName = ownerDisplayName
        self.participants = participants
        self.isDeleted = isDeleted
    }
}

extension ShareSummary {
    /// O resumo de um convite que chegou do CloudKit.
    init(_ share: CKShare) {
        self.init(
            zone: CloudZoneID(share.recordID.zoneID),
            title: share[CKShare.SystemFieldKey.title] as? String,
            url: share.url,
            currentUserPermission: CloudKitMapping.permission(of: share.currentUserParticipant),
            ownerDisplayName: CloudKitMapping.displayName(from: share.owner.userIdentity.nameComponents),
            participants: share.participants.filter { $0.role != .owner }.map { Participant($0) })
    }
}

extension ShareSummary.Participant {
    init(_ participant: CKShare.Participant) {
        self.init(
            displayName: CloudKitMapping.displayName(from: participant.userIdentity.nameComponents),
            userRecordName: participant.userIdentity.userRecordID?.recordName,
            // Sem permissão conhecida vale o menos que se pode dar: só ver.
            permission: BoardCloudInfo.Permission(participant.permission) ?? .readOnly,
            isAccepted: participant.acceptanceStatus == .accepted)
    }
}

extension BoardCloudInfo.Permission {
    /// A permissão de edição ou de leitura que o CloudKit deu a um participante; `nil` para `.none` e `.unknown`.
    init?(_ permission: CKShare.ParticipantPermission) {
        switch permission {
        case .readWrite: self = .readWrite
        case .readOnly: self = .readOnly
        case .none, .unknown: return nil
        @unknown default: return nil
        }
    }
}

extension PendingChange {
    /// A pendência do `CKSyncEngine`, ou `nil` se for de um tipo que esta build não conhece.
    init?(_ change: CKSyncEngine.PendingRecordZoneChange) {
        switch change {
        case .saveRecord(let id): self = .save(CloudRecordID(id))
        case .deleteRecord(let id): self = .delete(CloudRecordID(id))
        @unknown default: return nil
        }
    }

    var engineChange: CKSyncEngine.PendingRecordZoneChange {
        switch self {
        case .save(let id): .saveRecord(id.ckRecordID)
        case .delete(let id): .deleteRecord(id.ckRecordID)
        }
    }
}

/// As traduções entre o que o `CKSyncEngine` entrega e o que o `BoardSyncCoordinator` recebe. Ficam em funções puras, fora do motor,
/// para serem testadas sem iCloud: o motor em si só as chama e devolve o resultado.
enum CloudKitMapping {
    /// A mensagem de `SyncSaveFailure.other` quando o servidor devolve um registro que não converte.
    static let unreadableServerRecord = "registro do servidor ilegível"

    // MARK: Envio

    /// O resultado de um envio, no vocabulário do coordenador.
    struct SendOutcome: Equatable {
        /// Os registros aceitos, com os campos de sistema que o servidor deu.
        var saved: [CloudRecord] = []
        /// Os registros apagados; apagar o que já não existe (`unknownItem`) conta como apagado.
        var deleted: [CloudRecordID] = []
        var failures: [SyncSaveFailure] = []
        /// O que falhou por um motivo passageiro (`CloudKitMapping.isTransient`): não vai ao coordenador como recusa e continua na fila
        /// do motor, que tenta de novo com a própria espera. Fica fora de `zones`, para a troca de pendências não o tirar da fila.
        var retriedByEngine: Set<PendingChange> = []

        /// As zonas do que o coordenador recebe do evento (aceitos, apagados e recusas).
        var zones: Set<CloudZoneID> {
            var zones = Set(saved.map(\.id.zone))
            zones.formUnion(deleted.map(\.zone))
            zones.formUnion(failures.map(\.zone))
            return zones
        }

        /// Os registros que o iCloud recusou sem que a recusa mude nada na próxima tentativa (cota, permissão, erro desconhecido):
        /// reenviar na hora só repetiria a recusa, em laço. Voltam na próxima chamada de `add(_:)`.
        var refused: Set<CloudRecordID> {
            var refused = Set<CloudRecordID>()
            for failure in failures {
                switch failure {
                case .quotaExceeded(let id), .permission(let id), .other(let id, _): refused.insert(id)
                case .conflict, .unknownItem, .zoneMissing: break
                }
            }
            return refused
        }
    }

    /// Converte o resultado de um envio. Um registro aceito que não converte fica de fora (a pendência dele continua, e o próximo envio
    /// traz o conflito com a marca nova).
    static func sendOutcome(
        savedRecords: [CKRecord],
        failedSaves: [(record: CKRecord, error: CKError)],
        deletedRecordIDs: [CKRecord.ID],
        failedDeletes: [CKRecord.ID: CKError]
    ) -> SendOutcome {
        var outcome = SendOutcome()
        for record in savedRecords {
            do {
                outcome.saved.append(try CloudRecord(record))
            } catch {
                Logger.sync.error(
                    "Registro aceito sem conversão: \(record.recordID.recordName, privacy: .public) (\(String(describing: error), privacy: .public))"
                )
            }
        }
        outcome.deleted = deletedRecordIDs.map(CloudRecordID.init)
        for failure in failedSaves {
            if isTransient(failure.error) {
                outcome.retriedByEngine.insert(.save(CloudRecordID(failure.record.recordID)))
            } else {
                outcome.failures.append(saveFailure(for: failure.error, recordID: failure.record.recordID))
            }
        }
        for (recordID, error) in failedDeletes.sorted(by: { isOrdered($0.key, $1.key) }) {
            if error.code == .unknownItem {
                outcome.deleted.append(CloudRecordID(recordID))
            } else if isTransient(error) {
                outcome.retriedByEngine.insert(.delete(CloudRecordID(recordID)))
            } else {
                outcome.failures.append(saveFailure(for: error, recordID: recordID))
            }
        }
        return outcome
    }

    /// Erros que passam sozinhos (sem rede, servidor ocupado ou fora do ar, limite de pedidos, resposta perdida, conta indisponível
    /// por um momento, operação cancelada): reenviar depois resolve, então a mudança não é recusa nem sai da fila. Tratá-los como
    /// recusa deixaria a mudança parada até a próxima gravação do mural.
    static let transientErrorCodes: Set<CKError.Code> = [
        .networkFailure, .networkUnavailable, .serviceUnavailable, .zoneBusy, .requestRateLimited, .serverResponseLost,
        .notAuthenticated, .accountTemporarilyUnavailable, .operationCancelled,
    ]

    static func isTransient(_ error: CKError) -> Bool {
        transientErrorCodes.contains(error.code)
    }

    /// A recusa do CloudKit no vocabulário do coordenador: conflito (com a versão do servidor), registro sumido, zona sumida, cota,
    /// permissão e o resto. Um conflito cuja versão do servidor não converte ou não veio vira `.other`.
    static func saveFailure(for error: CKError, recordID: CKRecord.ID) -> SyncSaveFailure {
        let id = CloudRecordID(recordID)
        switch error.code {
        case .serverRecordChanged:
            guard let serverRecord = error.serverRecord else { return .other(id, "conflito sem o registro do servidor") }
            do {
                return .conflict(serverRecord: try CloudRecord(serverRecord))
            } catch {
                Logger.sync.error(
                    "Conflito sem conversão: \(recordID.recordName, privacy: .public) (\(String(describing: error), privacy: .public))")
                return .other(id, unreadableServerRecord)
            }
        case .unknownItem:
            return .unknownItem(id)
        case .zoneNotFound, .userDeletedZone:
            return .zoneMissing(id.zone)
        case .quotaExceeded:
            return .quotaExceeded(id)
        case .permissionFailure:
            return .permission(id)
        default:
            return .other(id, "erro do iCloud (código \(error.code.rawValue))")
        }
    }

    // MARK: Busca

    /// O que uma busca trouxe, no vocabulário do coordenador.
    struct FetchOutcome: Equatable {
        var saved: [CloudRecord] = []
        var deleted: [CloudRecordID] = []
        /// Os convites da leva, os gravados primeiro e os apagados depois (o último de cada zona vale). Não vão ao coordenador: quem
        /// os recebe é o app, pelo `CloudKitSyncEngine.setShareHandler(_:)`.
        var shares: [ShareSummary] = []

        /// As zonas dos registros que seguem para o coordenador: só nelas as pendências do motor são trocadas pelas dele. Os convites
        /// ficam de fora, porque não têm pendência.
        var zones: Set<CloudZoneID> {
            Set(saved.map(\.id.zone)).union(deleted.map(\.zone))
        }
    }

    /// Um registro apagado da zona, com o tipo que ele tinha (`CKSyncEngine.Event.FetchedRecordZoneChanges.deletions`).
    typealias RecordDeletion = (recordID: CKRecord.ID, recordType: CKRecord.RecordType)

    /// Converte o que uma busca trouxe. Registro que não converte fica de fora da leva (e só o nome dele vai ao registro de
    /// diagnóstico), para um registro ilegível não derrubar os outros. Os convites são separados antes (`separatingShares`): o
    /// CloudKit os entrega junto com os registros, e como tipo desconhecido eles viriam como ilegíveis.
    static func fetchOutcome(modifications: [CKRecord], deletions: [RecordDeletion]) -> FetchOutcome {
        var outcome = FetchOutcome()
        let (records, shares) = separatingShares(from: modifications)
        for record in records {
            do {
                outcome.saved.append(try CloudRecord(record))
            } catch {
                Logger.sync.error(
                    "Registro ignorado: \(record.recordID.recordName, privacy: .public) (\(String(describing: error), privacy: .public))")
            }
        }
        let (removed, removedShares) = separatingShareDeletions(from: deletions)
        outcome.deleted = removed.map(CloudRecordID.init)
        outcome.shares = shares + removedShares
        return outcome
    }

    // MARK: Convite

    /// Separa os convites dos registros do mural. O convite tem tipo próprio (`CKRecord.SystemType.share`) e vem na mesma leva, na
    /// busca e na busca completa. Um convite que não chega como `CKShare` não tem como ser resumido: sai da leva do mesmo jeito (não é
    /// registro do mural) e o fato vai ao registro de diagnóstico.
    static func separatingShares(from records: [CKRecord]) -> (records: [CKRecord], shares: [ShareSummary]) {
        var muralRecords: [CKRecord] = []
        var shares: [ShareSummary] = []
        for record in records {
            guard record.recordType == CKRecord.SystemType.share else {
                muralRecords.append(record)
                continue
            }
            if let share = record as? CKShare {
                shares.append(ShareSummary(share))
            } else {
                Logger.sync.error("Convite sem resumo na zona \(record.recordID.zoneID.zoneName, privacy: .public)")
            }
        }
        return (muralRecords, shares)
    }

    /// Reconhece o apagamento do convite (o dono parou de compartilhar) entre os registros apagados: pelo tipo da deleção ou pelo nome
    /// do registro de convite da zona. O resto são apagamentos de registros do mural.
    static func separatingShareDeletions(from deletions: [RecordDeletion]) -> (deleted: [CKRecord.ID], shares: [ShareSummary]) {
        var deleted: [CKRecord.ID] = []
        var shares: [ShareSummary] = []
        for deletion in deletions {
            if deletion.recordType == CKRecord.SystemType.share || deletion.recordID.recordName == CKRecordNameZoneWideShare {
                shares.append(ShareSummary(zone: CloudZoneID(deletion.recordID.zoneID), isDeleted: true))
            } else {
                deleted.append(deletion.recordID)
            }
        }
        return (deleted, shares)
    }

    /// A permissão desta pessoa no convite (`CKShare.currentUserParticipant`): dono, ou a permissão do participante; `nil` se ela não
    /// é participante.
    static func permission(of participant: CKShare.Participant?) -> BoardCloudInfo.Permission? {
        participant.flatMap { permission(role: $0.role, permission: $0.permission) }
    }

    static func permission(role: CKShare.ParticipantRole, permission: CKShare.ParticipantPermission) -> BoardCloudInfo.Permission? {
        role == .owner ? .owner : BoardCloudInfo.Permission(permission)
    }

    /// O nome de uma pessoa do convite, no formato da região; `nil` se o iCloud não deu nome.
    static func displayName(from components: PersonNameComponents?) -> String? {
        guard let name = components?.formatted(), !name.isEmpty else { return nil }
        return name
    }

    // MARK: Zona apagada

    /// Por que a zona apagada deixou de existir para este Mac. No banco compartilhado, toda zona que some é acesso perdido (o dono
    /// apagou, parou de compartilhar ou removeu esta pessoa). No privado, `.deleted` é o dono apagando o mural ou parando de
    /// compartilhá-lo em outro Mac dele, e `.purged` e `.encryptedDataReset` são a pessoa apagando os dados do app no iCloud ou
    /// redefinindo os dados criptografados.
    static func removalReason(
        for reason: CKDatabase.DatabaseChange.Deletion.Reason, in scope: CloudDatabaseScope
    ) -> BoardRemovalReason {
        guard scope == .private else { return .accessRevoked }
        switch reason {
        case .deleted: return .zoneDeleted
        case .purged, .encryptedDataReset: return .cloudDataErased
        @unknown default: return .zoneDeleted
        }
    }

    // MARK: Interno

    /// Ordem fixa: dono, zona e nome do registro.
    private static func isOrdered(_ lhs: CKRecord.ID, _ rhs: CKRecord.ID) -> Bool {
        [lhs.zoneID.ownerName, lhs.zoneID.zoneName, lhs.recordName].lexicographicallyPrecedes([
            rhs.zoneID.ownerName, rhs.zoneID.zoneName, rhs.recordName,
        ])
    }
}
