import CloudKit
import Foundation
import os

extension Logger {
    /// O registro do motor de sincronização. Só vão para ele o nome do mural (da zona), o nome do registro, o tipo do evento e o
    /// código do erro; nunca o conteúdo de um cartão.
    static let sync = Logger(subsystem: "com.joaocosta.Mural", category: "Sincronização")
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

        /// As zonas de tudo o que o evento trouxe.
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
            outcome.failures.append(saveFailure(for: failure.error, recordID: failure.record.recordID))
        }
        for (recordID, error) in failedDeletes.sorted(by: { isOrdered($0.key, $1.key) }) {
            if error.code == .unknownItem {
                outcome.deleted.append(CloudRecordID(recordID))
            } else {
                outcome.failures.append(saveFailure(for: error, recordID: recordID))
            }
        }
        return outcome
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

        /// As zonas dos registros que seguem para o coordenador: só nelas as pendências do motor são trocadas pelas dele.
        var zones: Set<CloudZoneID> {
            Set(saved.map(\.id.zone)).union(deleted.map(\.zone))
        }
    }

    /// Converte o que uma busca trouxe. Registro que não converte fica de fora da leva (e só o nome dele vai ao registro de
    /// diagnóstico), para um registro ilegível não derrubar os outros.
    static func fetchOutcome(modifications: [CKRecord], deletions: [CKRecord.ID]) -> FetchOutcome {
        var outcome = FetchOutcome()
        for record in modifications {
            do {
                outcome.saved.append(try CloudRecord(record))
            } catch {
                Logger.sync.error(
                    "Registro ignorado: \(record.recordID.recordName, privacy: .public) (\(String(describing: error), privacy: .public))")
            }
        }
        outcome.deleted = deletions.map(CloudRecordID.init)
        return outcome
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
