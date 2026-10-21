import Foundation

public enum WorkspaceValidationIssue: Equatable, Sendable {
    case invalidPath(index: Int)
    case repeatedPathID(UUID)
    case pathTruncated(index: Int)
    case nonFiniteZoom
    case zoomClamped
    case nonFiniteCanvasCenter
    case invalidFilter
    case removedReadingPosition(UUID)
    case removedOpenStretches(UUID)
    case contentRevisionAdjusted
}
