import Foundation

/// Dados de um cartão de link: o endereço e a prévia buscada da própria página.
public struct LinkInfo: Codable, Hashable, Sendable {
    /// Endereço da página (`http` ou `https`).
    public var url: URL
    /// Título lido da própria página; `nil` até a prévia ser buscada.
    public var pageTitle: String?
    /// Nome do site, como a página o declara.
    public var siteName: String?
    /// Texto de prévia: a descrição da página.
    public var summary: String?
    /// Endereço da imagem de prévia na web: a que o Safari entrega ao arrastar ou a da própria página.
    /// A cópia local fica em `previewImageFile`.
    public var remoteImageURL: URL?
    /// Nome do arquivo da imagem de prévia, guardado fora da pasta de itens.
    public var previewImageFile: String?
    /// Nome do arquivo do ícone do site, guardado fora da pasta de itens.
    public var iconFile: String?
    /// Situação da busca da prévia.
    public var preview: LinkPreviewState

    public init(
        url: URL,
        pageTitle: String? = nil,
        siteName: String? = nil,
        summary: String? = nil,
        remoteImageURL: URL? = nil,
        previewImageFile: String? = nil,
        iconFile: String? = nil,
        preview: LinkPreviewState = .pending
    ) {
        self.url = url
        self.pageTitle = pageTitle
        self.siteName = siteName
        self.summary = summary
        self.remoteImageURL = remoteImageURL
        self.previewImageFile = previewImageFile
        self.iconFile = iconFile
        self.preview = preview
    }

    /// Só `url` é obrigatória; o resto assume o padrão quando falta, para o formato poder
    /// ganhar campos sem invalidar murais já gravados. Chaves desconhecidas são ignoradas.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(URL.self, forKey: .url)
        pageTitle = try container.decodeIfPresent(String.self, forKey: .pageTitle)
        siteName = try container.decodeIfPresent(String.self, forKey: .siteName)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        remoteImageURL = try container.decodeIfPresent(URL.self, forKey: .remoteImageURL)
        previewImageFile = try container.decodeIfPresent(String.self, forKey: .previewImageFile)
        iconFile = try container.decodeIfPresent(String.self, forKey: .iconFile)
        preview = try container.decodeIfPresent(LinkPreviewState.self, forKey: .preview) ?? .pending
    }
}

/// Situação da prévia (título, imagem e ícone) buscada da página do link.
public enum LinkPreviewState: Codable, Hashable, Sendable {
    /// Ainda não foi buscada.
    case pending
    /// Buscada com sucesso na data indicada.
    case ready(fetchedAt: Date)
    /// A última tentativa falhou na data indicada; `attempts` conta as tentativas feitas.
    case failed(at: Date, attempts: Int)
}

/// Link ainda não inserido no mural, vindo de colar ou arrastar.
public struct LinkDraft: Hashable, Sendable {
    public var url: URL
    /// Título sugerido pela origem; sem ele, o cartão usa o host do endereço.
    public var title: String?
    /// Texto de prévia que já veio com o link; vazio ou só com espaços é ignorado.
    public var summary: String?
    /// Imagem de prévia que já veio com o link (a que o Safari entrega ao arrastar); só vale `http` ou `https`.
    public var imageURL: URL?

    public init(url: URL, title: String? = nil, summary: String? = nil, imageURL: URL? = nil) {
        self.url = url
        self.title = title
        self.summary = summary
        self.imageURL = imageURL
    }
}
