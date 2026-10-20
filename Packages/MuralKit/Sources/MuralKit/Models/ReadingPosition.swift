import Foundation

/// Tipo de conteúdo para o qual uma posição de leitura pode ser guardada.
public enum ReadingPositionKind: String, Codable, Equatable, Sendable {
    case collection
    case item
    case pdf
}

/// Posição de leitura de uma coleção, item ou página PDF.
public struct ReadingPosition: Codable, Equatable, Sendable {
    public var targetID: BoardID
    public var kind: ReadingPositionKind
    public var page: Int?
    public var progress: Double?

    public init(
        targetID: BoardID,
        kind: ReadingPositionKind,
        page: Int? = nil,
        progress: Double? = nil
    ) {
        self.targetID = targetID
        self.kind = kind
        self.page = page
        self.progress = progress
    }

    public init(collectionID: BoardID, progress: Double? = nil) {
        self.init(targetID: collectionID, kind: .collection, progress: progress)
    }

    public init(itemID: BoardID, progress: Double? = nil) {
        self.init(targetID: itemID, kind: .item, progress: progress)
    }

    public init(pdfID: BoardID, page: Int, progress: Double? = nil) {
        self.init(targetID: pdfID, kind: .pdf, page: page, progress: progress)
    }

    public var itemID: BoardID { targetID }
    public var id: BoardID { targetID }
    public var pdfPage: Int? {
        get { page }
        set { page = newValue }
    }
    public var offset: Double? {
        get { progress }
        set { progress = newValue }
    }
}
