import Foundation

/// Um nível aberto por cima do mural: uma pasta (coleção) ou um item (detalhe).
enum Destination: Hashable, Identifiable {
    case collection(UUID)
    case item(UUID)

    var id: UUID {
        switch self {
        case .collection(let id), .item(let id): id
        }
    }
}
