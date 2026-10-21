import Foundation

/// Pedido de prévia para um cartão de link.
public struct LinkPreviewRequest: Hashable, Sendable {
    /// Cartão que receberá a prévia.
    public var itemID: UUID
    /// Endereço da página.
    public var url: URL
    /// Imagem que já veio com o link (a do Safari ao copiar um favorito); o buscador pode tentá-la primeiro.
    public var remoteImageURL: URL?
    /// Quantas tentativas anteriores falharam; 0 na primeira busca.
    public var previousAttempts: Int
    /// Pedido de "Atualizar prévia": o buscador ignora `remoteImageURL`, que é a imagem de antes, e procura
    /// a imagem de novo na própria página.
    public var isRefresh: Bool

    public init(itemID: UUID, url: URL, remoteImageURL: URL? = nil, previousAttempts: Int = 0, isRefresh: Bool = false) {
        self.itemID = itemID
        self.url = url
        self.remoteImageURL = remoteImageURL
        self.previousAttempts = previousAttempts
        self.isRefresh = isRefresh
    }
}

/// O que o buscador trouxe da página: textos, endereço da imagem e os bytes da imagem e do ícone.
/// Os bytes ainda não foram reduzidos nem gravados; isso é feito por `LinkPreviewFiles`.
public struct FetchedLinkPreview: Equatable, Sendable {
    public var title: String?
    public var siteName: String?
    public var summary: String?
    /// Endereço de onde veio a imagem de prévia.
    public var remoteImageURL: URL?
    public var imageData: Data?
    public var iconData: Data?

    public init(
        title: String? = nil,
        siteName: String? = nil,
        summary: String? = nil,
        remoteImageURL: URL? = nil,
        imageData: Data? = nil,
        iconData: Data? = nil
    ) {
        self.title = title
        self.siteName = siteName
        self.summary = summary
        self.remoteImageURL = remoteImageURL
        self.imageData = imageData
        self.iconData = iconData
    }
}

/// Busca a prévia de uma página. O app implementa este protocolo com a rede; os testes usam um buscador falso.
public protocol LinkPreviewFetching: Sendable {
    /// Busca a prévia ou lança erro. O cancelamento da tarefa deve interromper a busca.
    func fetchPreview(for request: LinkPreviewRequest) async throws -> FetchedLinkPreview
}
