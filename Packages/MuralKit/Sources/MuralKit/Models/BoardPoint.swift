import Foundation

/// Posição de um cartão no mural, em pontos, independente de SwiftUI.
public struct BoardPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = BoardPoint(x: 0, y: 0)
}
