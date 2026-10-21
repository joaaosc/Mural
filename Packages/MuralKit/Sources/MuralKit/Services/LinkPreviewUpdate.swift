import Foundation

/// Resultado de uma busca de prévia, pronto para ser aplicado ao cartão por `BoardModel.applyLinkPreviews(_:)`.
public struct LinkPreviewUpdate: Equatable, Sendable {
    public var itemID: UUID
    public var pageTitle: String?
    public var siteName: String?
    public var summary: String?
    public var remoteImageURL: URL?
    /// Nome do arquivo da imagem de prévia já gravado por `LinkPreviewFiles`.
    public var previewImageFile: String?
    /// Nome do arquivo do ícone já gravado por `LinkPreviewFiles`.
    public var iconFile: String?
    /// `.ready` quando a busca deu certo; `.failed` com os campos vazios quando falhou.
    public var state: LinkPreviewState

    public init(
        itemID: UUID,
        pageTitle: String? = nil,
        siteName: String? = nil,
        summary: String? = nil,
        remoteImageURL: URL? = nil,
        previewImageFile: String? = nil,
        iconFile: String? = nil,
        state: LinkPreviewState
    ) {
        self.itemID = itemID
        self.pageTitle = pageTitle
        self.siteName = siteName
        self.summary = summary
        self.remoteImageURL = remoteImageURL
        self.previewImageFile = previewImageFile
        self.iconFile = iconFile
        self.state = state
    }
}
