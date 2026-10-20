import Foundation

/// Snapshot Sendable transferido entre o actor de persistência e o domínio/UI.
public struct BoardRepositorySnapshot: Codable, Equatable, Sendable {
    public var manifest: BoardManifest
    public var board: Board
    public var workspace: BoardWorkspaceState

    public init(manifest: BoardManifest, board: Board, workspace: BoardWorkspaceState = .default) {
        self.manifest = manifest
        self.board = board
        self.workspace = workspace
    }

    public var id: BoardID { manifest.id }
}
