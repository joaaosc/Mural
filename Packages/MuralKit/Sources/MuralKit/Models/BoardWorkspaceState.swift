import Foundation

/// Estado navegacional persistível de um mural.
public struct BoardWorkspaceState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var contentRevision: Int
    public var canvas: CanvasWorkspaceState
    public var path: [WorkspaceDestination]
    public var filter: WorkspaceFilter?
    public var readingPositions: [UUID: ReadingPosition]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        contentRevision: Int = 0,
        canvas: CanvasWorkspaceState = CanvasWorkspaceState(),
        path: [WorkspaceDestination] = [],
        filter: WorkspaceFilter? = nil,
        readingPositions: [UUID: ReadingPosition] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.contentRevision = contentRevision
        self.canvas = canvas
        self.path = path
        self.filter = filter
        self.readingPositions = readingPositions
    }

    public static let `default` = BoardWorkspaceState()

    public var canvasState: CanvasWorkspaceState {
        get { canvas }
        set { canvas = newValue }
    }

    public var destinations: [WorkspaceDestination] {
        get { path }
        set { path = newValue }
    }
}
