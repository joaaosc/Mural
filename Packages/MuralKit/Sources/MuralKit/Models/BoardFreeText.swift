import Foundation

/// Texto curto que vive diretamente no mural, sem ser um cartão ou pertencer a uma pasta.
public struct BoardFreeText: Codable, Identifiable, Hashable, Sendable {
    /// Limite de armazenamento e edição, contado em `Character` para não cortar grafemas.
    public static let maximumCharacters = 280

    public var id: UUID
    public var text: String
    public var position: BoardPoint
    public var createdAt: Date
    /// Tamanho que a pessoa escolheu para o texto no mural; `nil` usa o quadrado padrão (`BoardLayout.freeTextSize`).
    /// Murais antigos não têm o campo.
    public var size: BoardSize?

    public init(
        id: UUID = UUID(),
        text: String,
        position: BoardPoint = .zero,
        createdAt: Date = .now,
        size: BoardSize? = nil
    ) {
        self.id = id
        self.text = Self.normalized(text)
        self.position = position
        self.createdAt = createdAt
        self.size = size
    }

    /// Remove espaços vazios nas pontas e limita o valor sem dividir caracteres compostos.
    public static func normalized(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maximumCharacters))
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, position, createdAt, size
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            text: try container.decode(String.self, forKey: .text),
            position: try container.decode(BoardPoint.self, forKey: .position),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            size: try container.decodeIfPresent(BoardSize.self, forKey: .size)
        )
    }
}
