import Foundation

/// Documento de lista: título, texto de abertura e seções com itens.
public struct ChecklistDocument: Codable, Hashable, Sendable {
    public var title: String
    public var intro: String
    public var sections: [ChecklistSection]

    public init(title: String, intro: String = "", sections: [ChecklistSection]) {
        self.title = title
        self.intro = intro
        self.sections = sections
    }

    /// Quantidade total de itens e quantos estão marcados.
    public var progress: (done: Int, total: Int) {
        var done = 0
        var total = 0
        for section in sections {
            for entry in section.entries {
                total += 1
                if entry.isDone { done += 1 }
            }
        }
        return (done, total)
    }

    public mutating func toggle(entryID: UUID) {
        for section in sections.indices {
            if let entry = sections[section].entries.firstIndex(where: { $0.id == entryID }) {
                sections[section].entries[entry].isDone.toggle()
                return
            }
        }
    }
}
