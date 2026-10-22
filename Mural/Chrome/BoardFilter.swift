import MuralKit

/// Destaque aplicado pelos botões da barra: os cartões fora do filtro ficam esmaecidos.
enum BoardFilter: String, CaseIterable, Identifiable {
    case notes
    case folders
    case tasks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes: "Notas"
        case .folders: "Pastas"
        case .tasks: "Listas"
        }
    }

    var symbol: String {
        switch self {
        case .notes: "text.document"
        case .folders: "folder"
        case .tasks: "checklist"
        }
    }

    func matches(_ kind: ItemKind) -> Bool {
        switch self {
        case .notes: kind == .text || kind == .sticky
        case .folders: kind == .folder
        case .tasks: kind == .checklist || kind == .reminder
        }
    }

    /// Destaque de um cartão sob este filtro (1 = normal): o que não combina fica esmaecido.
    func emphasis(for kind: ItemKind) -> Double {
        matches(kind) ? 1 : 0.25
    }

    /// Destaque de um cartão com o filtro de tipo e o de cor juntos: fica normal só quem passa nos dois;
    /// sem filtro nenhum, todos ficam normais.
    static func emphasis(for item: BoardItem, kind: BoardFilter?, color: TagColor?) -> Double {
        guard kind != nil || color != nil else { return 1 }
        let kindMatches = kind?.matches(item.kind) ?? true
        let colorMatches = color.map { item.colorTag == $0 } ?? true
        return kindMatches && colorMatches ? 1 : 0.25
    }

    /// Filtros que fazem sentido em cada nível: pastas também guardam pastas,
    /// e um item aberto sozinho não tem o que filtrar.
    static func available(at level: NavigationLevel) -> [BoardFilter] {
        switch level {
        case .board: allCases
        case .folder: [.folders, .notes, .tasks]
        case .item: []
        }
    }
}
