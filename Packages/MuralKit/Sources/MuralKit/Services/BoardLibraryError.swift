import Foundation

public enum BoardLibraryError: Error, Equatable, Sendable {
    case futureSchema(Int)
    case unavailableRoute(BoardRoute)
    case invalidPackage(URL)
    case corruptedLibraryState(String)
    case migrationRequiredButUnavailable
    case injectedFailure(BoardLibraryFaultPoint)
    case portable(BoardPortablePackageError)
    /// O nome pedido tem o que o macOS não aceita num nome de arquivo (`BoardName.issue(in:)`).
    case invalidName(BoardName.Issue)
    /// A localização do vídeo (nome do cartão) não pôde ser tirada da cópia para outras pessoas.
    case videoLocationNotRemoved(String)
    /// O dono da câmera, o número de série ou a localização da imagem (nome do cartão) não puderam ser tirados da cópia.
    case imageMetadataNotRemoved(String)
    case io(String)
}

public enum BoardLibraryFaultPoint: String, Codable, Equatable, Hashable, Sendable {
    case beforeDraftPublish
    case afterDraftPublish
    case beforePromotionPublish
    case afterPromotionPublish
    case beforeDiscardCleanup
}

public struct BoardLibraryFaultInjection: Sendable {
    public var points: Set<BoardLibraryFaultPoint>

    public init(points: Set<BoardLibraryFaultPoint> = []) {
        self.points = points
    }

    public static let none = BoardLibraryFaultInjection()

    mutating func consume(_ point: BoardLibraryFaultPoint) -> Bool {
        points.remove(point) != nil
    }
}
