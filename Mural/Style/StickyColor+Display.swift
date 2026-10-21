import MuralKit

extension StickyColor {
    /// Nome da cor para a acessibilidade e a dica do ponteiro.
    var displayName: String {
        switch self {
        case .yellow: "Amarelo"
        case .pink: "Rosa"
        case .orange: "Laranja"
        case .blue: "Azul"
        case .green: "Verde"
        }
    }
}
