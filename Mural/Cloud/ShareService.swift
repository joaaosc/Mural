import CloudKit
import CoreTransferable
import Foundation
import MuralKit
import MuralSync

/// O convite de pessoas para um mural pelo iCloud: cria ou busca o `CKShare` da zona do mural e o entrega ao compartilhamento do
/// sistema (`BoardShareItem`), que mostra quem tem acesso e a permissão de cada pessoa. Só existe com o iCloud de verdade
/// (`CloudSyncMode.cloudKit`); o container vem do controlador.
///
/// Não tem teste automático: o convite e o aceite são do CloudKit de verdade e só se conferem com duas contas do iCloud.
@MainActor
final class ShareService {
    private let container: CKContainer
    private let library: BoardLibrary
    /// O controlador é dono do serviço; a referência fraca evita o ciclo.
    private weak var sync: CloudSyncController?

    init(container: CKContainer, library: BoardLibrary, sync: CloudSyncController) {
        self.container = container
        self.library = library
        self.sync = sync
    }

    /// As opções do convite, decisões do dono do Mural: só pessoas convidadas (sem link aberto a qualquer um) e a permissão escolhida
    /// por pessoa (editar ou só ver). Quem recebe o convite não convida outras pessoas, e quem não foi convidado pode pedir acesso.
    nonisolated static func allowedOptions() -> CKAllowedSharingOptions {
        let options = CKAllowedSharingOptions(
            allowedParticipantPermissionOptions: .any, allowedParticipantAccessOptions: .specifiedRecipientsOnly)
        options.allowsParticipantsToInviteOthers = false
        options.allowsAccessRequests = true
        return options
    }

    /// O item que o botão Convidar entrega ao compartilhamento do sistema. Com o convite já carregado (`existingShare`) o sistema
    /// abre a tela de gerenciar; sem ele, pede `prepareShare(for:)` na hora de convidar.
    func item(for id: BoardID, share: CKShare?) -> BoardShareItem {
        BoardShareItem(boardID: id, container: container, share: share, service: self)
    }

    /// O convite do mural, na hora de convidar: põe o mural no iCloud se preciso (sem esperar o primeiro envio), garante a zona no
    /// servidor e devolve o convite que já existe ou cria um, com o nome do mural como título e sem acesso público. Uma falha vira
    /// aviso para a pessoa e segue para o sistema, que não abre a tela de convidar.
    /// - Throws: `CloudSyncControllerError` (mural fora do iCloud, só deste Mac ou de outra pessoa) ou o que o CloudKit lançar.
    func prepareShare(for id: BoardID) async throws -> CKShare {
        do {
            return try await makeShare(for: id)
        } catch {
            sync?.postInvitationNotice("Não foi possível preparar o convite: \(error.localizedDescription)")
            throw error
        }
    }

    /// O convite que o iCloud já tem do mural, ou `nil` se o mural ainda não foi compartilhado. Serve para abrir a tela de gerenciar.
    /// Um convite achado também atualiza `shareStates`, com quem tem acesso agora.
    func existingShare(for id: BoardID) async throws -> CKShare? {
        let share = try await fetchShare(in: Self.zoneID(for: id))
        if let share { sync?.systemSharingDidSave(ShareSummary(share)) }
        return share
    }

    // MARK: Interno

    private func makeShare(for id: BoardID) async throws -> CKShare {
        guard let sync else { throw CloudSyncControllerError.disabled }
        try await sync.enableCloud(.saved(id))
        let zoneID = Self.zoneID(for: id)
        try await ensureZone(zoneID)
        let share: CKShare
        if let existing = try await fetchShare(in: zoneID) {
            share = existing
        } else {
            share = try await createShare(in: zoneID, titled: try await boardName(of: id))
        }
        sync.systemSharingDidSave(ShareSummary(share))
        return share
    }

    private static func zoneID(for id: BoardID) -> CKRecordZone.ID {
        CloudZoneID(name: CloudSchema.zoneName(for: id)).ckZoneID
    }

    /// Cria a zona no servidor, se ainda não existir: o convite mora nela, e o motor só a cria no envio dele. Salvar uma zona que já
    /// existe não muda nada.
    private func ensureZone(_ zoneID: CKRecordZone.ID) async throws {
        let result = try await container.privateCloudDatabase.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        _ = try result.saveResults[zoneID]?.get()
    }

    /// O convite da zona inteira (`CKRecordNameZoneWideShare`); `nil` quando a zona ainda não tem convite ou nem existe.
    private func fetchShare(in zoneID: CKRecordZone.ID) async throws -> CKShare? {
        let recordID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        do {
            return try await container.privateCloudDatabase.record(for: recordID) as? CKShare
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            return nil
        }
    }

    private func createShare(in zoneID: CKRecordZone.ID, titled title: String) async throws -> CKShare {
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = title as NSString
        share.publicPermission = .none
        let result = try await container.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
        guard let saved = try result.saveResults[share.recordID]?.get() as? CKShare else { throw ShareServiceError.shareNotSaved }
        return saved
    }

    private func boardName(of id: BoardID) async throws -> String {
        let route = BoardRoute.saved(id)
        guard let snapshot = try await library.open(route) else { throw BoardLibraryError.unavailableRoute(route) }
        return snapshot.manifest.name
    }
}

enum ShareServiceError: LocalizedError {
    /// O iCloud não devolveu o convite que acabou de ser salvo.
    case shareNotSaved

    var errorDescription: String? {
        switch self {
        case .shareNotSaved: "O iCloud não confirmou o convite deste mural."
        }
    }
}

/// O mural que o botão Convidar entrega ao compartilhamento do sistema (`ShareLink`). O sistema pede o convite pelo
/// `CKShareTransferRepresentation`, fora do Main Actor: por isso o tipo é `nonisolated` e só leva valores que atravessam threads.
nonisolated struct BoardShareItem: Transferable, Sendable {
    let boardID: BoardID
    let container: CKContainer
    /// O convite já carregado, se o mural já foi compartilhado; `nil` manda o sistema preparar um na hora.
    let share: CKShare?
    let service: ShareService

    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { (item: BoardShareItem) in
            if let share = item.share {
                return .existing(share, container: item.container, allowedSharingOptions: ShareService.allowedOptions())
            }
            return .prepareShare(container: item.container, allowedSharingOptions: ShareService.allowedOptions()) {
                try await item.service.prepareShare(for: item.boardID)
            }
        }
    }
}
