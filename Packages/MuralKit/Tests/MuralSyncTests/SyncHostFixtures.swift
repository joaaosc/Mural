import Foundation
import MuralKit
import MuralSync

/// Segura uma chamada do host de teste até o teste liberar, para provar o que o coordenador faz enquanto o host está juntando.
actor SyncTestGate {
    private var isHolding = false
    private var isReleased = false
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    /// Chamado pelo host: avisa que chegou e espera o teste liberar.
    func hold() async {
        isHolding = true
        for waiter in arrivalWaiters { waiter.resume() }
        arrivalWaiters = []
        guard !isReleased else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    /// Chamado pelo teste: espera o host chegar ao ponto de espera.
    func waitUntilHolding() async {
        guard !isHolding else { return }
        await withCheckedContinuation { arrivalWaiters.append($0) }
    }

    func release() {
        isReleased = true
        for waiter in releaseWaiters { waiter.resume() }
        releaseWaiters = []
    }
}

/// O app de mentira dos testes de sincronização: guarda os murais em memória, junta o que chega com `BoardMerge.apply` (como o app
/// de verdade fará), copia os arquivos para `Items/` e registra o que o coordenador pediu.
actor SyncTestHost: BoardSyncHost {
    struct Removal: Equatable {
        var board: BoardID
        var reason: BoardRemovalReason
    }

    private struct Entry {
        var name: String
        var board: Board
        var itemsDirectory: URL
    }

    private var entries: [BoardID: Entry] = [:]
    private var gate: SyncTestGate?
    private var failuresLeft = 0

    /// Cada chamada de `applyRemote`, na ordem em que foi concluída.
    private(set) var received: [ReceivedChanges] = []
    private(set) var removals: [Removal] = []

    func add(_ id: BoardID, name: String, board: Board, itemsDirectory: URL) {
        entries[id] = Entry(name: name, board: board, itemsDirectory: itemsDirectory)
    }

    func board(_ id: BoardID) -> Board {
        entries[id]?.board ?? Board()
    }

    func name(_ id: BoardID) -> String {
        entries[id]?.name ?? ""
    }

    /// Uma edição local: o app grava o mural.
    func write(_ board: Board, for id: BoardID) {
        entries[id]?.board = board
    }

    func rename(_ name: String, for id: BoardID) {
        entries[id]?.name = name
    }

    /// As próximas `count` chamadas de `applyRemote` falham como uma gravação em disco que não deu certo: o mural fica como estava.
    func failNextApply(_ count: Int = 1) {
        failuresLeft = count
    }

    /// A próxima chamada de `applyRemote` espera o teste liberar `gate`, antes de mexer no mural.
    func hold(_ gate: SyncTestGate) {
        self.gate = gate
    }

    // MARK: BoardSyncHost

    func localBoard(_ id: BoardID) -> LocalBoardSnapshot? {
        entries[id].map { LocalBoardSnapshot(name: $0.name, board: $0.board, itemsDirectory: $0.itemsDirectory) }
    }

    func applyRemote(_ id: BoardID, received changes: ReceivedChanges) async throws {
        if let gate {
            self.gate = nil
            await gate.hold()
        }
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw CocoaError(.fileWriteOutOfSpace)
        }
        received.append(changes)
        guard var entry = entries[id] else { return }
        entry.board = BoardMerge.apply(changes.changes, to: entry.board, base: changes.previousBase).board
        entry.name = changes.mergedName(local: entry.name)
        for (file, source) in changes.files {
            let destination = entry.itemsDirectory.appendingPathComponent(file, isDirectory: false)
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.copyItem(at: source, to: destination)
        }
        entries[id] = entry
    }

    func boardRemoved(_ id: BoardID, reason: BoardRemovalReason) {
        removals.append(Removal(board: id, reason: reason))
    }
}
