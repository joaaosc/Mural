import Foundation

/// Sessão mínima de domínio para que sair de um mural descarregue somente o
/// snapshot daquele mural.
public actor BoardSession {
    public let id: BoardID
    public let repository: BoardRepository
    public private(set) var board: Board
    public private(set) var workspace: BoardWorkspaceState
    public private(set) var manifest: BoardManifest

    public init(snapshot: BoardRepositorySnapshot, repository: BoardRepository) {
        self.id = snapshot.id
        self.repository = repository
        self.board = snapshot.board
        self.workspace = snapshot.workspace
        self.manifest = snapshot.manifest
    }

    public func update(board: Board? = nil, workspace: BoardWorkspaceState? = nil, manifest: BoardManifest? = nil) {
        if let board { self.board = board }
        if let workspace { self.workspace = workspace }
        if let manifest { self.manifest = manifest }
    }

    @discardableResult
    public func flush() async throws -> BoardRepositorySnapshot {
        let snapshot = BoardRepositorySnapshot(
            manifest: manifest,
            board: board,
            workspace: workspace
        )
        try await repository.save(snapshot)
        return snapshot
    }

    @discardableResult
    public func prepareToLeave() async throws -> BoardRepositorySnapshot {
        try await flush()
    }
}
