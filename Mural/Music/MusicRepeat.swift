/// Repetição do tocador. O valor `nil` do tocador (estações, por exemplo) é "indisponível".
enum MusicRepeat: Equatable, Sendable {
    case none
    case all
    case one

    /// O próximo estado do botão de repetir: nenhuma, tudo, uma e de volta à nenhuma.
    var next: MusicRepeat {
        switch self {
        case .none: .all
        case .all: .one
        case .one: .none
        }
    }
}
