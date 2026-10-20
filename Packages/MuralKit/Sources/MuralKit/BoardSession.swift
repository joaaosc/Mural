import Foundation

/// Sessão mínima de domínio para que sair de um mural descarregue somente o
/// snapshot daquele mural.
public actor BoardSession {
    public let id: BoardID
    public let repository: BoardRepository
    public private(set) var board: Board
    public private(set) var workspace: BoardWorkspaceState
    public private(set) var manifest: BoardManifest
    public private(set) var generation: UInt64 = 0
    public private(set) var isDirty = false
    public private(set) var isFlushInProgress = false
    public private(set) var lastFlushErrorDescription: String?

    public init(snapshot: BoardRepositorySnapshot, repository: BoardRepository) {
        self.id = snapshot.id
        self.repository = repository
        self.board = snapshot.board
        self.workspace = snapshot.workspace
        self.manifest = snapshot.manifest
    }

    /// Inicia uma mutação e devolve a geração observada pelo caller.
    @discardableResult
    public func beginMutation(_ kind: BoardSessionMutationKind = .content) throws -> UInt64 {
        guard !isFlushInProgress else { throw BoardSessionError.flushInProgress }
        return generation
    }

    /// Aplica uma mutação tipada. Revisões só avançam quando o valor realmente muda.
    public func update(
        board: Board? = nil,
        workspace: BoardWorkspaceState? = nil,
        expectedGeneration: UInt64? = nil
    ) throws {
        guard !isFlushInProgress else { throw BoardSessionError.flushInProgress }
        if let expectedGeneration, expectedGeneration != generation {
            throw BoardSessionError.generationMismatch(expected: expectedGeneration, actual: generation)
        }
        let contentChanged = board != nil && board != self.board
        let workspaceChanged = workspace != nil && workspace != self.workspace
        guard contentChanged || workspaceChanged else { return }

        if let board, contentChanged { self.board = board }
        if let workspace, workspaceChanged { self.workspace = workspace }
        if contentChanged { manifest.contentRevision += 1 }
        if workspaceChanged { manifest.workspaceRevision += 1 }
        self.workspace.contentRevision = manifest.contentRevision
        generation &+= 1
        isDirty = true
        lastFlushErrorDescription = nil
    }

    @discardableResult
    public func flush() async throws -> BoardRepositorySnapshot {
        guard !isFlushInProgress else { throw BoardSessionError.flushInProgress }
        guard isDirty else {
            return BoardRepositorySnapshot(manifest: manifest, board: board, workspace: workspace)
        }
        isFlushInProgress = true
        let capturedGeneration = generation
        let snapshot = BoardRepositorySnapshot(manifest: manifest, board: board, workspace: workspace)
        do {
            try await repository.save(snapshot)
            if generation == capturedGeneration {
                isDirty = false
            }
            isFlushInProgress = false
            lastFlushErrorDescription = nil
            return snapshot
        } catch {
            isFlushInProgress = false
            isDirty = true
            lastFlushErrorDescription = String(describing: error)
            throw error
        }
    }

    @discardableResult
    public func prepareToLeave() async throws -> BoardRepositorySnapshot {
        try await flush()
    }
}
