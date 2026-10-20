import Foundation

/// Identidade estável de um mural. O wrapper impede que um UUID de cartão seja
/// usado acidentalmente como o diretório de outro mural.
public struct BoardID: Codable, Hashable, Identifiable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public var id: UUID { rawValue }
    public var description: String { rawValue.uuidString }
}
