import MuralKit

/// Destaque aplicado pelos três botões da barra: os cartões fora do filtro ficam esmaecidos.
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
        case .notes: "list.bullet"
        case .folders: "number.sign"
        case .tasks: "checkmark"
        }
    }

    func matches(_ kind: ItemKind) -> Bool {
        switch self {
        case .notes: kind == .text || kind == .sticky
        case .folders: kind == .folder
        case .tasks: kind == .checklist
        }
    }
}
