import Foundation

/// Âncora persistida do canvas. `.origin` é diferente de um centro lógico em
/// `(0, 0)`, evitando que ausência de estado seja confundida com uma posição.
public enum CanvasWorkspaceAnchor: Codable, Equatable, Sendable {
    case origin
    case logicalCenter(BoardPoint)
}
