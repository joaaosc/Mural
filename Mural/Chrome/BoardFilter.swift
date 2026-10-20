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
        case .tasks: kind == .checklist
        }
    }

    /// Opacidade de um cartão sob este filtro: o que não combina fica esmaecido.
    func opacity(for kind: ItemKind) -> Double {
        matches(kind) ? 1 : 0.25
    }

    /// Filtros que fazem sentido em cada nível: dentro de uma pasta não há pastas,
    /// e um item aberto sozinho não tem o que filtrar.
    static func available(at level: NavigationLevel) -> [BoardFilter] {
        switch level {
        case .board: allCases
        case .folder: [.notes, .tasks]
        case .item: []
        }
    }
}
