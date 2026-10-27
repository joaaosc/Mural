import Foundation
import MuralKit
import MuralSync

/// O que o app pede ao motor de sincronização de um banco do iCloud, igual para o motor de verdade (`CloudKitSyncEngine`) e para o
/// falso dos testes de interface (`InMemorySyncEngine`): o controlador não precisa saber qual dos dois está usando.
protocol CloudSyncEngine: Sendable {
    /// Liga o motor. Antes disso o `CloudKitSyncEngine` recusa as demais chamadas.
    func start() async throws

    /// Acrescenta o que o coordenador diz estar pendente.
    func add(_ changes: Set<PendingChange>) async throws

    /// Cria no iCloud a zona do mural. Só o dono, no banco privado.
    @discardableResult
    func startZone(for boardID: BoardID) async throws -> CloudZoneID

    /// Apaga do iCloud a zona do mural. Só o dono, no banco privado.
    func deleteZone(for boardID: BoardID) async throws

    /// O convidado deixa o mural: apaga o próprio convite no iCloud, e a zona some para ele sem afetar o dono. Só no banco
    /// compartilhado. Quem chama faz antes `declineZone(of:)` e `stopTracking` no coordenador.
    func leave(_ zone: CloudZoneID) async throws

    /// Envia agora o que está pendente.
    func send() async throws

    /// Busca agora o que mudou no iCloud.
    func fetch() async throws

    /// Liga quem recebe os convites (`ShareSummary`) que as buscas trazem. O fecho roda no executor do motor e deve voltar logo; vale
    /// ligá-lo antes de `start()`, para nenhum convite se perder.
    func setShareHandler(_ handler: @escaping @Sendable ([ShareSummary]) -> Void) async
}

extension CloudKitSyncEngine: CloudSyncEngine {
    func leave(_ zone: CloudZoneID) async throws {
        try leaveZone(zone)
    }

    func send() async throws {
        try await sendNow()
    }

    func fetch() async throws {
        try await fetchNow()
    }
}

extension InMemorySyncEngine: CloudSyncEngine {
    /// O motor falso não tem agenda nem estado a restaurar: nada a ligar.
    func start() async throws {}

    // `deleteZone(for:)` é do próprio motor falso (apaga a zona no `InMemoryCloud`), e já cumpre o protocolo: não há adaptador.

    func leave(_ zone: CloudZoneID) async throws {
        await leaveZone(zone)
    }

    func send() async throws {
        try await sendChanges()
    }

    func fetch() async throws {
        try await fetchChanges()
    }
}
