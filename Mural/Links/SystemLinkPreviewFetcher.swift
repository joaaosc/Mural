import Foundation
import LinkPresentation
import MuralKit

/// Por que uma busca de prévia não deu nada.
nonisolated enum LinkPreviewFetchError: Error, Equatable {
    /// O endereço não é `http` nem `https`.
    case unsupportedAddress
    /// O servidor respondeu com um status fora de 200–299.
    case badStatus(Int)
    /// Nem a página, nem a imagem, nem o ícone, nem a reserva trouxeram título, resumo, imagem ou ícone.
    case nothingUseful
}

/// Busca a prévia de um link na rede: lê o começo da página (`<head>`), baixa a imagem e o ícone e, se
/// faltar título ou imagem, pede ao LinkPresentation o que faltou.
///
/// - O endereço `http` é trocado por `https`; o app não tem exceção de ATS. Se a página só existir em `http`,
///   a busca falha: nem a reserva recebe o endereço `http`.
/// - A página é lida até 512 KB (e só até o `</head>`), a imagem até 5 MB e o ícone até 512 KB. O que passar
///   disso é recusado, mesmo sem `Content-Length` e mesmo vindo da reserva.
/// - Uma imagem só serve se o ImageIO a lê e ela tem tamanho de prévia (`LinkPreviewFiles.canStoreImage(_:)`);
///   uma de 1×1 pixel do Safari, por exemplo, passa a vez para a `og:image`.
/// - A imagem que veio com o link (a do Safari ao arrastar) vale mais que a `og:image` da página, menos num pedido
///   de atualização (`LinkPreviewRequest.isRefresh`), que a ignora e procura a imagem de novo na página.
/// - O `<head>` tem prioridade; a reserva só completa o que faltar.
nonisolated struct SystemLinkPreviewFetcher: LinkPreviewFetching {
    /// Reserva: recebe o endereço da página e devolve o que achou, ou `nil`.
    typealias Fallback = @Sendable (URL) async throws -> FetchedLinkPreview?

    /// Bytes lidos da página, no máximo.
    static let pageByteLimit = 512 * 1024
    /// Bytes de uma imagem de prévia, no máximo.
    static let imageByteLimit = 5 * 1024 * 1024
    /// Bytes de um ícone, no máximo.
    static let iconByteLimit = 512 * 1024
    /// Quantos ícones declarados na página são tentados antes do `/favicon.ico`.
    static let maximumDeclaredIcons = 5

    private static let headEnd = Array("</head".utf8)
    private static let imageAccept = "image/*,*/*;q=0.8"

    /// Sessão das buscas reais: uma só para o app inteiro, porque cada janela de mural cria o seu buscador.
    static let sharedSession = URLSession(configuration: defaultConfiguration())

    /// A sessão desta instância. Fica visível para os testes conferirem que o padrão é a compartilhada.
    let session: URLSession
    private let fallback: Fallback

    /// - Parameters:
    ///   - session: sessão das buscas; por padrão a compartilhada (`sharedSession`), e os testes injetam uma com
    ///     um `URLProtocol` de mentira.
    ///   - fallback: reserva; a padrão usa o `LinkMetadata` do LinkPresentation.
    init(session: URLSession = SystemLinkPreviewFetcher.sharedSession, fallback: @escaping Fallback = systemFallback) {
        self.session = session
        self.fallback = fallback
    }

    // MARK: Configuração

    /// Sessão sem cookies, credenciais nem cache, com prazos curtos e sem esperar a rede voltar.
    ///
    /// Pede HTML e envia os idiomas do usuário em `Accept-Language`, para o site responder no idioma dele.
    static func defaultConfiguration(languages: [String] = Locale.preferredLanguages) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        var headers = ["Accept": "text/html,application/xhtml+xml;q=0.9,*/*;q=0.8"]
        if let acceptLanguage = acceptLanguage(for: languages) { headers["Accept-Language"] = acceptLanguage }
        configuration.httpAdditionalHeaders = headers
        return configuration
    }

    /// Valor de `Accept-Language` para os idiomas em ordem de preferência (no máximo 5):
    /// `pt-BR, en-US;q=0.9, fr;q=0.8`. Sem idiomas, `nil`.
    static func acceptLanguage(for languages: [String]) -> String? {
        let tags = languages.prefix(5).enumerated().map { index, tag in
            index == 0 ? tag : "\(tag);q=\(String(format: "%.1f", 1.0 - Double(index) * 0.1))"
        }
        return tags.isEmpty ? nil : tags.joined(separator: ", ")
    }

    /// Reserva padrão: o LinkPresentation (macOS 26.4 ou mais novo) entrega título, imagem e ícone, em 1 a 6 s.
    static let systemFallback: Fallback = { url in
        let metadata = try await LinkMetadata(fetching: url, timeout: .seconds(15))
        // Sem imagem ou sem ícone ainda vale o título.
        let image = try? await metadata.media(.image, as: Data.self)
        let icon = try? await metadata.media(.icon, as: Data.self)
        return FetchedLinkPreview(title: metadata.title, imageData: image, iconData: icon)
    }

    // MARK: Busca

    func fetchPreview(for request: LinkPreviewRequest) async throws -> FetchedLinkPreview {
        guard let pageURL = WebLink.secureVariant(of: request.url) else { throw LinkPreviewFetchError.unsupportedAddress }
        try Task.checkCancellation()

        // 1. A página. Falha comum (rede, status, tamanho) não impede a imagem do Safari nem a reserva.
        var page: Page?
        var pageFailure: (any Error)?
        do {
            page = try await loadPage(at: pageURL)
        } catch {
            try Task.checkCancellation()
            pageFailure = error
        }
        let head = page?.head ?? HTMLHeadMetadata()
        var preview = FetchedLinkPreview(title: head.title, siteName: head.siteName, summary: head.summary)

        // 2. A imagem: a do Safari, a `og:image` ou a própria página, nessa ordem. Num pedido de atualização a do
        // Safari (ou a da busca anterior) fica de fora: o que se quer é a imagem que a página tem agora.
        var imageURLs = [request.isRefresh ? nil : request.remoteImageURL, head.imageURL].compactMap { $0 }
        var loadedImages: [URL: Data] = [:]
        if let page, let data = page.image {
            imageURLs.append(page.url)
            loadedImages[page.url] = data
        }
        if let image = try await firstImage(in: imageURLs, alreadyLoaded: loadedImages) {
            preview.imageData = image.data
            preview.remoteImageURL = image.url
        }

        // 3. O ícone: os da página, em ordem, e por fim o `/favicon.ico` da origem. Se a página nem abriu, a
        // origem não é confiável: nada é pedido a ela.
        var iconURLs = Array(head.iconURLs.prefix(Self.maximumDeclaredIcons))
        if let page, let favicon = Self.faviconURL(for: page.url) { iconURLs.append(favicon) }
        preview.iconData = try await firstIcon(in: iconURLs)

        // 4. A reserva, só se faltar título ou imagem, e só para o que faltar. Ela só recebe o endereço `https`,
        // nunca o `http` original, mesmo quando a página não abriu.
        if preview.title == nil || preview.imageData == nil {
            preview = try await completing(preview, from: pageURL)
        }

        guard preview.title != nil || preview.summary != nil || preview.imageData != nil || preview.iconData != nil else {
            throw pageFailure ?? LinkPreviewFetchError.nothingUseful
        }
        return preview
    }

    // MARK: Página

    /// O que a página trouxe.
    private struct Page {
        var head = HTMLHeadMetadata()
        /// Os bytes da própria página, quando ela é uma imagem.
        var image: Data?
        /// Endereço final, depois dos redirecionamentos: a base dos endereços relativos.
        var url: URL
    }

    private func loadPage(at url: URL) async throws -> Page {
        let output = try await BoundedDownload.load(URLRequest(url: url), using: session) { response in
            guard (200..<300).contains(response.statusCode) else { throw LinkPreviewFetchError.badStatus(response.statusCode) }
            switch ContentKind(response) {
            case .html:
                return BoundedDownload.Plan(maximumBytes: Self.pageByteLimit, failsAboveMaximum: false, endMarker: Self.headEnd)
            case .image:
                return BoundedDownload.Plan(maximumBytes: Self.imageByteLimit, failsAboveMaximum: true)
            case .other:
                return nil
            }
        }
        let finalURL = output.response.url ?? url
        switch ContentKind(output.response) {
        case .html:
            let head = HTMLHeadMetadata.parse(output.data, baseURL: finalURL, textEncodingName: output.response.textEncodingName)
            return Page(head: head, url: finalURL)
        case .image:
            return Page(image: output.data, url: finalURL)
        case .other:
            return Page(url: finalURL)
        }
    }

    /// O tipo de conteúdo da página, pelo `Content-Type`. Sem ele, trata como HTML, como os navegadores.
    private enum ContentKind {
        case html
        case image
        case other

        init(_ response: HTTPURLResponse) {
            let type = response.mimeType?.lowercased() ?? "text/html"
            if type == "text/html" || type == "application/xhtml+xml" {
                self = .html
            } else if type.hasPrefix("image/") {
                self = .image
            } else {
                self = .other
            }
        }
    }

    // MARK: Imagem e ícone

    /// A primeira imagem que serve de prévia: a que já foi baixada (a própria página) ou a que baixa agora, até
    /// 5 MB, e que o ImageIO lê com lado menor de 32 px ou mais e até 40 milhões de pixels. Uma imagem que o ImageIO
    /// lê mas que a gravação recusaria (um pixel de rastreamento, por exemplo) passa a vez para a seguinte.
    /// Endereços `http` viram `https` e cada endereço é tentado uma vez.
    private func firstImage(in urls: [URL], alreadyLoaded: [URL: Data]) async throws -> (data: Data, url: URL)? {
        var tried = Set<URL>()
        for url in urls {
            let secure = WebLink.secureVariant(of: url) ?? url
            guard tried.insert(secure).inserted else { continue }
            try Task.checkCancellation()
            var data = alreadyLoaded[secure]
            if data == nil { data = try await downloadFile(at: secure, byteLimit: Self.imageByteLimit) }
            if let data, LinkPreviewFiles.canStoreImage(data) { return (data, secure) }
        }
        return nil
    }

    /// O primeiro ícone que baixa (até 512 KB) e que serve: o ImageIO o lê, com lado menor de 16 px ou mais.
    private func firstIcon(in urls: [URL]) async throws -> Data? {
        var tried = Set<URL>()
        for url in urls {
            let secure = WebLink.secureVariant(of: url) ?? url
            guard tried.insert(secure).inserted else { continue }
            try Task.checkCancellation()
            if let data = try await downloadFile(at: secure, byteLimit: Self.iconByteLimit), LinkPreviewFiles.canStoreIcon(data) {
                return data
            }
        }
        return nil
    }

    /// Baixa um arquivo de prévia. Falha de rede, de status ou de tamanho devolve `nil`; só o cancelamento sobe.
    private func downloadFile(at url: URL, byteLimit: Int) async throws -> Data? {
        var request = URLRequest(url: url)
        request.setValue(Self.imageAccept, forHTTPHeaderField: "Accept")
        do {
            let output = try await BoundedDownload.load(request, using: session) { response in
                guard (200..<300).contains(response.statusCode) else { throw LinkPreviewFetchError.badStatus(response.statusCode) }
                return BoundedDownload.Plan(maximumBytes: byteLimit, failsAboveMaximum: true)
            }
            return output.data
        } catch {
            try Task.checkCancellation()
            return nil
        }
    }

    /// `/favicon.ico` na raiz da origem (esquema, host e porta) de `pageURL`.
    private static func faviconURL(for pageURL: URL) -> URL? {
        guard var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) else { return nil }
        components.user = nil
        components.password = nil
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    // MARK: Reserva

    /// Completa a prévia com o que a reserva achou, sem trocar nada que a página já deu. Falha da reserva,
    /// que não é cancelamento, só a deixa sem efeito. A reserva não limita o que devolve: imagem acima de 5 MB e
    /// ícone acima de 512 KB são descartados aqui, como seriam se viessem da rede.
    private func completing(_ preview: FetchedLinkPreview, from url: URL) async throws -> FetchedLinkPreview {
        try Task.checkCancellation()
        let extra: FetchedLinkPreview?
        do {
            extra = try await fallback(url)
        } catch {
            try Task.checkCancellation()
            return preview
        }
        guard let extra else { return preview }

        var merged = preview
        merged.title = merged.title ?? Self.nonBlank(extra.title)
        merged.siteName = merged.siteName ?? Self.nonBlank(extra.siteName)
        merged.summary = merged.summary ?? Self.nonBlank(extra.summary)
        if merged.imageData == nil, let data = extra.imageData, data.count <= Self.imageByteLimit {
            merged.imageData = data
            merged.remoteImageURL = extra.remoteImageURL
        }
        if merged.iconData == nil, let data = extra.iconData, data.count <= Self.iconByteLimit {
            merged.iconData = data
        }
        return merged
    }

    private static func nonBlank(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
