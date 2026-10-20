import Foundation

public struct LibraryState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var lifecycle: LibraryLifecycle
    public var stableWelcomeID: BoardID
    public var promotedBoardID: BoardID?

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        lifecycle: LibraryLifecycle = .intact,
        stableWelcomeID: BoardID = BoardID(),
        promotedBoardID: BoardID? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.lifecycle = lifecycle
        self.stableWelcomeID = stableWelcomeID
        self.promotedBoardID = promotedBoardID
    }
}
