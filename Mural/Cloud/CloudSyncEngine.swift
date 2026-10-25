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

    /// Envia agora o que está pendente.
    func send() async throws

    /// Busca agora o que mudou no iCloud.
    func fetch() async throws
}

extension CloudKitSyncEngine: CloudSyncEngine {
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

    func send() async throws {
        try await sendChanges()
    }

    func fetch() async throws {
        try await fetchChanges()
    }
}
