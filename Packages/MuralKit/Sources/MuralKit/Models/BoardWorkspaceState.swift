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

extension BoardWorkspaceState {
    /// Grava os dois dicionários no formato de sempre (lista plana chave, valor, chave, valor…), mas ordenados pelo id: a ordem de
    /// iteração de um `[UUID: …]` muda a cada execução, e a cópia do iCloud Drive compara bytes, então regravaria sem mudança real.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(contentRevision, forKey: .contentRevision)
        try container.encode(canvas, forKey: .canvas)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(filter, forKey: .filter)
        try Self.encodeFlat(readingPositions, into: &container, forKey: .readingPositions)
        try Self.encodeFlat(openStretches, into: &container, forKey: .openStretches)
    }

    private static func encodeFlat<Value: Encodable>(
        _ dictionary: [UUID: Value], into container: inout KeyedEncodingContainer<CodingKeys>, forKey key: CodingKeys
    ) throws {
        var list = container.nestedUnkeyedContainer(forKey: key)
        for (id, value) in dictionary.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            try list.encode(id)
            try list.encode(value)
        }
    }
}
