import Foundation

public enum BoardLibraryError: Error, Equatable, Sendable {
    case futureSchema(Int)
    case unavailableRoute(BoardRoute)
    case invalidPackage(URL)
    case corruptedLibraryState(String)
    case migrationRequiredButUnavailable
    case injectedFailure(BoardLibraryFaultPoint)
    case io(String)
}

public enum BoardLibraryFaultPoint: String, Codable, Equatable, Hashable, Sendable {
    case beforeDraftPublish
    case afterDraftPublish
    case beforePromotionPublish
    case afterPromotionPublish
    case beforeDiscardCleanup
}

public struct BoardLibraryFaultInjection: Sendable {
    public var points: Set<BoardLibraryFaultPoint>

    public init(points: Set<BoardLibraryFaultPoint> = []) {
        self.points = points
    }

    public static let none = BoardLibraryFaultInjection()

    mutating func consume(_ point: BoardLibraryFaultPoint) -> Bool {
        points.remove(point) != nil
    }
}
