import Foundation

/// Resultado explícito da canonicalização; correções nunca ficam silenciosas.
public struct WorkspaceValidationResult: Equatable, Sendable {
    public let state: BoardWorkspaceState
    public let issues: [WorkspaceValidationIssue]

    public init(state: BoardWorkspaceState, issues: [WorkspaceValidationIssue] = []) {
        self.state = state
        self.issues = issues
    }

    public var isValid: Bool { issues.isEmpty }
}
