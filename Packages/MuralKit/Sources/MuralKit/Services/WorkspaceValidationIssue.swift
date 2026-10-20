import Foundation

public enum WorkspaceValidationIssue: Equatable, Sendable {
    case invalidPath(index: Int)
    case repeatedPathID(BoardID)
    case pathTruncated(index: Int)
    case nonFiniteZoom
    case zoomClamped
    case nonFiniteCanvasCenter
    case invalidFilter
    case removedReadingPosition(BoardID)
    case contentRevisionAdjusted
}
