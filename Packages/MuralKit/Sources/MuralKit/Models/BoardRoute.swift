import Foundation

public enum BoardRoute: Codable, Hashable, Sendable {
    case library
    case welcomeDraft(BoardID)
    case saved(BoardID)
}
