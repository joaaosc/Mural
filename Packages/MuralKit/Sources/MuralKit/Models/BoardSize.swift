import Foundation

/// Tamanho de um elemento do mural, em pontos do mural, independente de SwiftUI.
public struct BoardSize: Codable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}
