import Foundation

/// Anexo de uma nota: uma imagem colada ou um cartão embutido. O tamanho em pixels deixa a leitura reservar o espaço certo
/// antes de o arquivo ser decodificado.
///
/// Um anexo é um arquivo de imagem em `Items/` ou um cartão embutido (`card`). O de cartão tem `fileName` no formato
/// `<UUID>.card`, que só serve de nome para a citação no texto: nenhum arquivo existe com ele, e os pixels são 0.
public struct NoteAttachment: Codable, Hashable, Sendable {
    /// Nome do arquivo em `Items/`, no formato `<UUID>.<extensão>`; num cartão embutido, `<UUID>.card` (sem arquivo).
    public var fileName: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// O cartão embutido, quando o anexo não é imagem. Murais anteriores à versão 13 não têm o campo.
    public var card: EmbeddedCard?

    public init(fileName: String, pixelWidth: Int, pixelHeight: Int, card: EmbeddedCard? = nil) {
        self.fileName = fileName
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.card = card
    }

    /// Verdadeiro quando o anexo é um cartão embutido, e não um arquivo de imagem.
    public var isCard: Bool { card != nil }

    /// O id citado no texto (`mural-card:<UUID>`), lido do nome; `nil` quando o anexo não é cartão ou o nome não é `<UUID>.card`.
    public var cardID: UUID? {
        guard isCard, NoteImageMarkup.isCardAttachmentName(fileName) else { return nil }
        return UUID(uuidString: String(fileName.dropLast(".card".count)))
    }

    private enum CodingKeys: String, CodingKey {
        case fileName, pixelWidth, pixelHeight, card
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            fileName: try container.decode(String.self, forKey: .fileName),
            pixelWidth: try container.decode(Int.self, forKey: .pixelWidth),
            pixelHeight: try container.decode(Int.self, forKey: .pixelHeight),
            card: try container.decodeIfPresent(EmbeddedCard.self, forKey: .card))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(pixelWidth, forKey: .pixelWidth)
        try container.encode(pixelHeight, forKey: .pixelHeight)
        try container.encodeIfPresent(card, forKey: .card)
    }
}
