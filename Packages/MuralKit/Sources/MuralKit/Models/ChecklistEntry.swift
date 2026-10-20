import Foundation

/// Um item marcável de uma lista.
public struct ChecklistEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var text: String
    public var isDone: Bool

    public init(id: UUID = UUID(), text: String, isDone: Bool = false) {
        self.id = id
        self.text = text
        self.isDone = isDone
    }
}
