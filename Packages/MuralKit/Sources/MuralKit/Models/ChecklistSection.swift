import Foundation

/// Grupo de itens sob um título (por exemplo, "Living Room").
public struct ChecklistSection: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var entries: [ChecklistEntry]

    public init(id: UUID = UUID(), title: String, entries: [ChecklistEntry]) {
        self.id = id
        self.title = title
        self.entries = entries
    }
}
