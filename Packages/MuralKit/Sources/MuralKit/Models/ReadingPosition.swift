import Foundation

/// Posição persistida de leitura. IDs de conteúdo são UUIDs de `BoardItem`;
/// `BoardID` fica reservado para a identidade do mural.
public enum ReadingPosition: Codable, Equatable, Sendable {
    case collection(
        folderID: UUID,
        firstVisibleItemID: UUID?,
        relativeOffset: Double,
        fallbackContentY: Double
    )
    case item(itemID: UUID, visibleContentY: Double)
    case pdf(itemID: UUID, pageIndex: Int, scale: Double, pointInPage: BoardPoint)

    public var targetItemID: UUID {
        switch self {
        case .collection(let folderID, _, _, _): folderID
        case .item(let itemID, _), .pdf(let itemID, _, _, _): itemID
        }
    }
}
