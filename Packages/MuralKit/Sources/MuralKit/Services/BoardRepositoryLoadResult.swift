import Foundation

public struct BoardRepositoryLoadResult: Equatable, Sendable {
    public let snapshot: BoardRepositorySnapshot
    public let workspaceStatus: BoardWorkspaceLoadStatus
    public let workspaceIssues: [WorkspaceValidationIssue]

    public init(
        snapshot: BoardRepositorySnapshot,
        workspaceStatus: BoardWorkspaceLoadStatus,
        workspaceIssues: [WorkspaceValidationIssue] = []
    ) {
        self.snapshot = snapshot
        self.workspaceStatus = workspaceStatus
        self.workspaceIssues = workspaceIssues
    }
}
