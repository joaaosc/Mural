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

    /// Sem efeito: o motor falso não deixa o `InMemoryCloud` ao alcance do app para apagar a zona. Nenhum teste precisa disso
    /// hoje; quem montar o ambiente e precisar apaga pelo `InMemoryCloud.deleteZone`.
    func deleteZone(for boardID: BoardID) async throws {}

    func send() async throws {
        try await sendChanges()
    }

    func fetch() async throws {
        try await fetchChanges()
    }
}
