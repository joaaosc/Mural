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
    /// Parágrafos abertos por nota (ou abertura de lista).
    public var openStretches: [UUID: OpenStretchMemory]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        contentRevision: Int = 0,
        canvas: CanvasWorkspaceState = CanvasWorkspaceState(),
        path: [WorkspaceDestination] = [],
        filter: WorkspaceFilter? = nil,
        readingPositions: [UUID: ReadingPosition] = [:],
        openStretches: [UUID: OpenStretchMemory] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.contentRevision = contentRevision
        self.canvas = canvas
        self.path = path
        self.filter = filter
        self.readingPositions = readingPositions
        self.openStretches = openStretches
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, contentRevision, canvas, path, filter, readingPositions, openStretches
    }

    public static let `default` = BoardWorkspaceState()

    public var destinations: [WorkspaceDestination] {
        get { path }
        set { path = newValue }
    }
}

extension BoardWorkspaceState {
    /// Estados gravados antes de `openStretches` existir abrem com a memória vazia.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            contentRevision: try container.decode(Int.self, forKey: .contentRevision),
            canvas: try container.decode(CanvasWorkspaceState.self, forKey: .canvas),
            path: try container.decode([WorkspaceDestination].self, forKey: .path),
            filter: try container.decodeIfPresent(WorkspaceFilter.self, forKey: .filter),
            readingPositions: try container.decode([UUID: ReadingPosition].self, forKey: .readingPositions),
            openStretches: try container.decodeIfPresent([UUID: OpenStretchMemory].self, forKey: .openStretches) ?? [:])
    }
}
