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
        let all = sections.flatMap(\.entries)
        return (all.filter(\.isDone).count, all.count)
    }

    public mutating func toggle(entryID: UUID) {
        for s in sections.indices {
            if let e = sections[s].entries.firstIndex(where: { $0.id == entryID }) {
                sections[s].entries[e].isDone.toggle()
                return
            }
        }
    }

    /// Prefixos que marcam uma linha como item de lista.
    static let bulletPrefixes = ["- [ ] ", "- [x] ", "- [X] ", "- ", "* ", "• ", "[ ] ", "[x] "]

    /// Diz se o texto parece uma lista: pelo menos duas linhas com marcador.
    public static func looksLikeChecklist(_ text: String) -> Bool {
        let bulletLines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in bulletPrefixes.contains { line.hasPrefix($0) } }
        return bulletLines.count >= 2
    }

    /// Monta um documento a partir de texto simples.
    ///
    /// Regras: a primeira linha sem marcador vira o título; linhas sem marcador
    /// depois de um item abrem uma nova seção; `- [x]` entra já marcado.
    public static func parse(_ text: String) -> ChecklistDocument {
        var title = ""
        var intro: [String] = []
        var sections: [ChecklistSection] = []
        var current: ChecklistSection?

        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if let prefix = bulletPrefixes.first(where: { line.hasPrefix($0) }) {
                let body = String(line.dropFirst(prefix.count))
                let done = prefix.lowercased().contains("[x]")
                if current == nil { current = ChecklistSection(title: "", entries: []) }
                current?.entries.append(ChecklistEntry(text: body, isDone: done))
            } else if title.isEmpty {
                title = line.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
            } else if let open = current {
                sections.append(open)
                current = ChecklistSection(title: line, entries: [])
            } else if sections.isEmpty, current == nil, intro.isEmpty || !intro.isEmpty {
                // Texto entre o título e a primeira seção.
                if current == nil, sections.isEmpty, !looksLikeSectionHeader(line, next: nil) {
                    intro.append(line)
                } else {
                    current = ChecklistSection(title: line, entries: [])
                }
            }
        }
        if let open = current { sections.append(open) }
        return ChecklistDocument(title: title.isEmpty ? "Lista" : title, intro: intro.joined(separator: " "), sections: sections)
    }

    private static func looksLikeSectionHeader(_ line: String, next: String?) -> Bool {
        // Linha curta sem ponto final tende a ser título de seção; parágrafo tende a ser introdução.
        line.count <= 40 && !line.hasSuffix(".")
    }
}
