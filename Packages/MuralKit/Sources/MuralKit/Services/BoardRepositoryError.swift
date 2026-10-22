import Foundation

public enum BoardRepositoryError: Error, Equatable, Sendable {
    case invalidBoardID
    case boardNotFound(BoardID)
    case corruptedManifest(String)
    case corruptedBoard(String)
    case futureManifestSchema(Int)
    case futureWorkspaceSchema(Int)
    case staleRevision(currentContent: Int, incomingContent: Int, currentWorkspace: Int, incomingWorkspace: Int)
    case conflictingRevision(content: Int, workspace: Int)
    case identityMismatch(expected: BoardID, actual: BoardID)
    case injectedFailure(BoardRepositoryFaultPoint)
    /// Arquivo de mídia referenciado pelo board que não existe em `Items/`.
    case missingAsset(String)
    case io(String)
}
