import Foundation

public enum BoardSessionMutationKind: Sendable {
    case content
    case workspace
    case contentAndWorkspace
}

public enum BoardSessionError: Error, Equatable, Sendable {
    case flushInProgress
    case generationMismatch(expected: UInt64, actual: UInt64)
    /// A sessão foi fechada (janela fechada, rascunho promovido): não grava mais nada.
    case retired
}
