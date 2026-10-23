import Foundation

/// Tipo do item do Apple Music que um cartão de música guarda.
public enum MusicItemKind: String, Codable, Sendable, CaseIterable {
    case album, song, playlist, station
}

/// Último estado conhecido de um álbum, faixa, playlist ou estação do Apple Music, guardado no cartão.
public struct MusicSnapshot: Codable, Hashable, Sendable {
    public var kind: MusicItemKind
    /// Id no catálogo do Apple Music (número do álbum ou da faixa, `pl.…`, `ra.…`); `nil` em playlist própria ou faixa só local.
    public var catalogID: String?
    /// Loja do catálogo (`br`, `us`), quando veio.
    public var storefront: String?
    /// Nome da playlist própria, quando ela chegou só pelo nome (arrasto da biblioteca).
    public var libraryPlaylistName: String?
    /// Id local da playlist própria achada na biblioteca. Só vale neste Mac; nunca interpretar o conteúdo.
    public var libraryID: String?
    /// Endereço `music.apple.com` do item.
    public var url: URL?
    public var title: String
    /// Artista (álbum, faixa) ou curador (playlist).
    public var subtitle: String?
    /// Álbum da faixa.
    public var albumTitle: String?
    /// Molde do endereço da capa, com `{w}`, `{h}` e `{f}`.
    public var artworkTemplate: String?
    /// Nome do arquivo da capa guardada pelo Mural (fora da pasta de itens).
    public var artworkFile: String?
    /// Cores da capa no formato `#rrggbb`.
    public var backgroundHex: String?
    public var primaryTextHex: String?
    public var secondaryTextHex: String?
    public var trackCount: Int?
    /// Data de lançamento como veio (`AAAA-MM-DD`).
    public var releaseDate: String?
    /// Duração em segundos (faixa).
    public var duration: TimeInterval?

    public init(
        kind: MusicItemKind,
        catalogID: String? = nil,
        storefront: String? = nil,
        libraryPlaylistName: String? = nil,
        libraryID: String? = nil,
        url: URL? = nil,
        title: String,
        subtitle: String? = nil,
        albumTitle: String? = nil,
        artworkTemplate: String? = nil,
        artworkFile: String? = nil,
        backgroundHex: String? = nil,
        primaryTextHex: String? = nil,
        secondaryTextHex: String? = nil,
        trackCount: Int? = nil,
        releaseDate: String? = nil,
        duration: TimeInterval? = nil
    ) {
        self.kind = kind
        self.catalogID = catalogID
        self.storefront = storefront
        self.libraryPlaylistName = libraryPlaylistName
        self.libraryID = libraryID
        self.url = url
        self.title = title
        self.subtitle = subtitle
        self.albumTitle = albumTitle
        self.artworkTemplate = artworkTemplate
        self.artworkFile = artworkFile
        self.backgroundHex = backgroundHex
        self.primaryTextHex = primaryTextHex
        self.secondaryTextHex = secondaryTextHex
        self.trackCount = trackCount
        self.releaseDate = releaseDate
        self.duration = duration
    }

    /// Só `kind` e `title` são obrigatórios; o resto assume `nil` quando falta, para o formato
    /// poder ganhar campos sem invalidar murais já gravados. Chaves desconhecidas são ignoradas.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(MusicItemKind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        catalogID = try container.decodeIfPresent(String.self, forKey: .catalogID)
        storefront = try container.decodeIfPresent(String.self, forKey: .storefront)
        libraryPlaylistName = try container.decodeIfPresent(String.self, forKey: .libraryPlaylistName)
        libraryID = try container.decodeIfPresent(String.self, forKey: .libraryID)
        url = try container.decodeIfPresent(URL.self, forKey: .url)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        albumTitle = try container.decodeIfPresent(String.self, forKey: .albumTitle)
        artworkTemplate = try container.decodeIfPresent(String.self, forKey: .artworkTemplate)
        artworkFile = try container.decodeIfPresent(String.self, forKey: .artworkFile)
        backgroundHex = try container.decodeIfPresent(String.self, forKey: .backgroundHex)
        primaryTextHex = try container.decodeIfPresent(String.self, forKey: .primaryTextHex)
        secondaryTextHex = try container.decodeIfPresent(String.self, forKey: .secondaryTextHex)
        trackCount = try container.decodeIfPresent(Int.self, forKey: .trackCount)
        releaseDate = try container.decodeIfPresent(String.self, forKey: .releaseDate)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
    }

    /// Normaliza uma cor para `#rrggbb` em minúsculas. Aceita com ou sem `#` e com espaços em volta;
    /// qualquer outra coisa devolve `nil`.
    public static func normalizedHex(_ text: String?) -> String? {
        guard var value = text?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.utf8.count == 6, value.utf8.allSatisfy({ $0.isASCIIHexDigit }) else { return nil }
        return "#" + value.lowercased()
    }

    /// Endereço da capa no tamanho pedido (lado em pontos de imagem), em `jpg`.
    /// `nil` sem molde, com molde sem `{w}`, com `side <= 0` ou se o resultado não for `http`/`https` com host.
    public func artworkURL(side: Int = 600) -> URL? {
        guard side > 0, let artworkTemplate, artworkTemplate.contains("{w}") else { return nil }
        let text =
            artworkTemplate
            .replacingOccurrences(of: "{w}", with: String(side))
            .replacingOccurrences(of: "{h}", with: String(side))
            .replacingOccurrences(of: "{f}", with: "jpg")
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https", let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    /// Há como mandar tocar: o item tem id de catálogo, id local ou nome de playlist própria.
    public var canPlay: Bool {
        catalogID != nil || libraryID != nil || libraryPlaylistName != nil
    }

    /// Chave para reconhecer o mesmo item arrastado duas vezes.
    public var dedupeKey: String {
        if let catalogID { return "\(kind.rawValue):catalog:\(catalogID)" }
        if let libraryPlaylistName { return "playlist:library:\(libraryPlaylistName.lowercased())" }
        return "\(kind.rawValue):title:\(title.lowercased())|\(subtitle?.lowercased() ?? "")"
    }
}

extension UInt8 {
    fileprivate var isASCIIHexDigit: Bool {
        (0x30...0x39).contains(self) || (0x41...0x46).contains(self) || (0x61...0x66).contains(self)
    }
}
