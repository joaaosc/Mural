/// Nível que está na frente: decide o formato da barra e os filtros disponíveis.
enum NavigationLevel {
    case board
    case folder
    case item

    init(path: [Destination]) {
        switch path.last {
        case nil: self = .board
        case .collection: self = .folder
        case .item: self = .item
        }
    }
}
