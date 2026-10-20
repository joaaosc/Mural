import Foundation

/// Metadados e revisões do pacote de um mural.
public struct BoardManifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: BoardID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var contentRevision: Int
    public var workspaceRevision: Int

    public init(
        id: BoardID,
        name: String = "Mural",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        contentRevision: Int = 0,
        workspaceRevision: Int = 0,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.contentRevision = contentRevision
        self.workspaceRevision = workspaceRevision
    }

    /// Alias semântico para callers que chamam a versão de formato.
    public var formatVersion: Int {
        get { schemaVersion }
        set { schemaVersion = newValue }
    }

    public var displayName: String {
        get { name }
        set { name = newValue }
    }
}
