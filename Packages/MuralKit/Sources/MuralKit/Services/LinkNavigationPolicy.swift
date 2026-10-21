import Foundation

/// Regras de navegação da página real aberta no detalhe de um cartão de link: o que continua dentro do app,
/// o que o sistema abre fora e o que é descartado.
///
/// É só a regra, sem WebKit nem interface: quem chama converte o pedido do WebKit nos parâmetros de
/// `decide(url:isMainFrame:opensNewWindow:shouldDownload:isUserInitiated:)` e a resposta do servidor nos de
/// `decide(canShowMimeType:url:isUserInitiated:)`.
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

    /// Esquemas de fora da web que um clique pode entregar ao sistema: e-mail, ligação, mensagem e FaceTime.
    /// Qualquer outro (links de apps, `itms-apps:`, `zoommtg:`...) é descartado.
    private static let externalSchemes: Set<String> = ["mailto", "tel", "sms", "facetime", "facetime-audio"]

    /// Decide o que fazer com um pedido de navegação (clique, redirecionamento, formulário, janela nova, download).
    ///
    /// - `http` e `https` seguem na página, exceto em janela nova e em download, que vão para o navegador.
    /// - No quadro principal, só `mailto:`, `tel:`, `sms:`, `facetime:` e `facetime-audio:` vão para o sistema;
    ///   qualquer outro esquema de fora da web (links de apps, por exemplo) é descartado, e a pessoa usa "Abrir
    ///   no navegador". Num quadro embutido (anúncio, vídeo) é permitido: quem decide sair do app é a página inteira.
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
        return isUserInitiated && externalSchemes.contains(scheme) ? .openExternally(url) : .cancel
    }

    /// Decide o que fazer com a resposta do servidor: o que o WebKit sabe mostrar continua na página; o resto
    /// (um arquivo para baixar, por exemplo) vai para o navegador, mas só se a pessoa pediu essa navegação. Uma
    /// página que dispara um download por conta própria, sem clique, tem a resposta descartada, e o mesmo vale
    /// sem endereço da web.
    ///
    /// - Parameters:
    ///   - canShowMimeType: o WebKit sabe mostrar o tipo da resposta.
    ///   - url: endereço da resposta.
    ///   - isUserInitiated: a resposta é a da última navegação que a pessoa pediu (ver `isSamePage(_:_:)`).
    public static func decide(canShowMimeType: Bool, url: URL?, isUserInitiated: Bool) -> Decision {
        if canShowMimeType { return .allow }
        guard isUserInitiated, let url, WebLink.isWeb(url) else { return .cancel }
        return .openExternally(url)
    }

    /// Indica se os dois endereços são da mesma página da web, para ligar a resposta do servidor à navegação que
    /// a pessoa pediu. Vale a `WebLink.dedupeKey`: o esquema (`http` ou `https`, porque o WebKit pode subir o
    /// esquema), `www.`, `#fragmento`, barra final e parâmetros de rastreamento não contam. Endereço ausente ou
    /// que não é da web nunca é igual a nada.
    public static func isSamePage(_ first: URL?, _ second: URL?) -> Bool {
        guard let first, let second, WebLink.isWeb(first), WebLink.isWeb(second) else { return false }
        return WebLink.dedupeKey(for: first) == WebLink.dedupeKey(for: second)
    }
}
