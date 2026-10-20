import Foundation

public enum BoardRepositoryError: Error, Equatable, Sendable {
    case invalidBoardID
    case boardNotFound(BoardID)
    case corruptedManifest(String)
    case corruptedBoard(String)
    case staleRevision(currentContent: Int, incomingContent: Int, currentWorkspace: Int, incomingWorkspace: Int)
    case identityMismatch(expected: BoardID, actual: BoardID)
    case io(String)
}
