import Foundation

/// Regras de navegação da página real aberta no detalhe de um cartão de link: o que continua dentro do app,
/// o que o sistema abre fora e o que é descartado.
///
/// É só a regra, sem WebKit nem interface: quem chama converte o pedido do WebKit nos parâmetros de
/// `decide(url:isMainFrame:opensNewWindow:shouldDownload:isUserInitiated:)` e a decisão na resposta do WebKit.
public enum LinkNavigationPolicy {
    /// O que fazer com uma navegação.
    public enum Decision: Equatable, Sendable {
        /// Continua dentro da página do app.
        case allow
        /// Não carrega no app: o endereço é entregue ao sistema (navegador, Mail ou o app que o trata).
        case openExternally(URL)
        /// Descarta, sem carregar nem abrir em lugar nenhum.
        case cancel
    }

    /// Esquemas que só existem dentro do WebKit (HTML local, dados embutidos, scripts): não há outro app para abri-los.
    private static let internalSchemes: Set<String> = ["about", "data", "blob", "javascript"]

    /// Decide o que fazer com um pedido de navegação (clique, redirecionamento, formulário, janela nova, download).
    ///
    /// - `http` e `https` seguem na página, exceto em janela nova e em download, que vão para o navegador.
    /// - Um esquema de fora da web no quadro principal (`mailto:`, `tel:`, links de apps) vai para o sistema.
    ///   Num quadro embutido (anúncio, vídeo) é permitido: quem decide sair do app é a página inteira.
    /// - `about:`, `data:`, `blob:` e `javascript:` nunca vão para o sistema: são permitidos, menos em janela nova
    ///   (não há onde abri-la). O `about:blank` é o endereço do HTML local carregado direto no app.
    /// - `file:` nunca é carregado nem aberto, e um download de fora da web é descartado.
    /// - Endereço ausente, ou `http`/`https` sem host, é descartado.
    ///
    /// - Parameters:
    ///   - url: endereço pedido.
    ///   - isMainFrame: o destino é a página inteira e não um quadro embutido.
    ///   - opensNewWindow: o pedido abriria uma janela nova (`target="_blank"`, `window.open`, ⌘-clique).
    ///   - shouldDownload: a página marcou o pedido como download.
    ///   - isUserInitiated: a pessoa pediu a navegação (clique num link, envio de formulário). Só um pedido assim
    ///     sai do app: uma página não abre janela, download ou outro app por conta própria. Por padrão, `true`.
    public static func decide(
        url: URL?, isMainFrame: Bool, opensNewWindow: Bool, shouldDownload: Bool, isUserInitiated: Bool = true
    ) -> Decision {
        guard let url, let scheme = url.scheme?.lowercased() else { return .cancel }

        if scheme == "http" || scheme == "https" {
            guard WebLink.isWeb(url) else { return .cancel }
            guard shouldDownload || opensNewWindow else { return .allow }
            return isUserInitiated ? .openExternally(url) : .cancel
        }

        // A partir daqui o esquema não é da web.
        if shouldDownload || scheme == "file" { return .cancel }
        if internalSchemes.contains(scheme) { return opensNewWindow ? .cancel : .allow }
        guard isMainFrame || opensNewWindow else { return .allow }
        return isUserInitiated ? .openExternally(url) : .cancel
    }

    /// Decide o que fazer com a resposta do servidor: o que o WebKit sabe mostrar continua na página; o resto
    /// (um arquivo para baixar, por exemplo) vai para o navegador, e sem endereço da web é descartado.
    public static func decide(canShowMimeType: Bool, url: URL?) -> Decision {
        if canShowMimeType { return .allow }
        guard let url, WebLink.isWeb(url) else { return .cancel }
        return .openExternally(url)
    }
}
