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
    /// Depois de aposentada (janela fechada, rascunho promovido), a sessão recusa
    /// mutações e gravações: um autosave atrasado não pode reescrever o package.
    public private(set) var isRetired = false

    public init(snapshot: BoardRepositorySnapshot, repository: BoardRepository) {
        self.id = snapshot.id
        self.repository = repository
        self.board = snapshot.board
        self.workspace = snapshot.workspace
        self.manifest = snapshot.manifest
    }

    /// Aplica uma mutação tipada. Revisões só avançam quando o valor realmente muda.
    public func update(
        board: Board? = nil,
        workspace: BoardWorkspaceState? = nil,
        expectedGeneration: UInt64? = nil
    ) throws {
        guard !isRetired else { throw BoardSessionError.retired }
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

    /// Renomeia o mural dentro da própria sessão, para que a gravação seguinte leve o
    /// nome novo. Fechar e reabrir a sessão deixaria um autosave antigo regravar o nome.
    public func rename(to name: String) throws {
        guard !isRetired else { throw BoardSessionError.retired }
        guard !isFlushInProgress else { throw BoardSessionError.flushInProgress }
        guard name != manifest.name else { return }
        manifest.name = name
        generation &+= 1
        isDirty = true
        lastFlushErrorDescription = nil
    }

    /// Troca o `cloud` do manifesto dentro da própria sessão, para a gravação seguinte levá-lo. Gravar o manifesto por fora, pela
    /// biblioteca, com a sessão aberta, não vale: a próxima gravação da sessão devolveria o `cloud` antigo ao disco. Não mexe nas
    /// revisões: o `cloud` não é conteúdo do mural.
    public func setCloud(_ cloud: BoardCloudInfo?) throws {
        guard !isRetired else { throw BoardSessionError.retired }
        guard !isFlushInProgress else { throw BoardSessionError.flushInProgress }
        guard cloud != manifest.cloud else { return }
        manifest.cloud = cloud
        generation &+= 1
        isDirty = true
        lastFlushErrorDescription = nil
    }

    /// Encerra a sessão. Idempotente.
    public func retire() {
        isRetired = true
    }

    @discardableResult
    public func flush() async throws -> BoardRepositorySnapshot {
        guard !isRetired else { throw BoardSessionError.retired }
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
