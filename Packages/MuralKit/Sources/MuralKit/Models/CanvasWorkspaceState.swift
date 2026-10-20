import Foundation

/// Estado confirmado do canvas, separado da escala visual transitória de uma pinça.
public struct CanvasWorkspaceState: Codable, Equatable, Sendable {
    public static let defaultZoom = 1.0
    public static let zoomRange = 0.4...2.5

    public var confirmedZoom: Double
    public var anchor: CanvasWorkspaceAnchor

    public init(
        confirmedZoom: Double = Self.defaultZoom,
        anchor: CanvasWorkspaceAnchor = .origin
    ) {
        self.confirmedZoom = confirmedZoom
        self.anchor = anchor
    }

    public init(confirmedZoom: Double = Self.defaultZoom, logicalCenter: BoardPoint?) {
        self.confirmedZoom = confirmedZoom
        self.anchor = logicalCenter.map(CanvasWorkspaceAnchor.logicalCenter) ?? .origin
    }

    public var logicalCenter: BoardPoint? {
        guard case .logicalCenter(let point) = anchor else { return nil }
        return point
    }

    public var isAtOrigin: Bool {
        if case .origin = anchor { return true }
        return false
    }
}
