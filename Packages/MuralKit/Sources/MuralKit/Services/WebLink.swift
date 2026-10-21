import Foundation

/// Reconhece e compara endereços da web (`http` e `https`), sem depender de interface.
public enum WebLink {
    private static let webSchemes: Set<String> = ["http", "https"]
    /// Parâmetros de rastreamento que não mudam a página; os `utm_*` são tratados à parte.
    private static let trackingParameters: Set<String> = ["fbclid", "gclid", "mc_cid", "mc_eid"]

    /// Extrai um único endereço da web de um texto colado, sem espaços e quebras nas pontas.
    ///
    /// Aceita `http://`, `https://` e `www.` sem esquema, que vira `https://www.…`. Devolve `nil`
    /// para texto com espaço no meio, outros esquemas (`javascript:`, `file:`, `mailto:`, `ftp:`,
    /// `data:`...), palavras soltas como `apple.com` e endereço sem host.
    public static func url(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        let start = trimmed.prefix(8).lowercased()
        let candidate: String
        if start.hasPrefix("https://") || start.hasPrefix("http://") {
            candidate = trimmed
        } else if start.hasPrefix("www."), !trimmed.dropFirst(4).isEmpty {
            candidate = "https://" + trimmed
        } else {
            return nil
        }
        guard let components = URLComponents(string: candidate), isWebAddress(components) else { return nil }
        return components.url
    }

    /// Indica se o endereço é `http` ou `https` e tem host.
    public static func isWeb(_ url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false).map(isWebAddress) ?? false
    }

    /// Chave que iguala endereços da mesma página escrita de formas diferentes: `http` e `https`,
    /// host em minúsculas e sem `www.`, porta padrão, `#fragmento`, barra final e parâmetros de
    /// rastreamento (`utm_*`, `fbclid`, `gclid`, `mc_cid`, `mc_eid`) não contam, e os demais
    /// parâmetros entram em ordem alfabética. O caminho continua diferenciando maiúsculas.
    /// Endereço que não é da web vira o próprio texto.
    public static func dedupeKey(for url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            isWebAddress(components), let host = components.host
        else { return url.absoluteString }

        var key = withoutWWW(host.lowercased())
        let defaultPort = components.scheme?.lowercased() == "https" ? 443 : 80
        if let port = components.port, port != defaultPort { key += ":\(port)" }
        var path = components.percentEncodedPath
        if path.hasSuffix("/") { path.removeLast() }
        key += path
        let parameters = (components.percentEncodedQueryItems ?? [])
            .filter { !isTracking($0.name) }
            .map { item in item.value.map { "\(item.name)=\($0)" } ?? item.name }
            .sorted()
        if !parameters.isEmpty { key += "?" + parameters.joined(separator: "&") }
        return key
    }

    /// Host para mostrar ao usuário: em minúsculas e sem `www.`. Sem host, o texto do endereço.
    public static func displayHost(of url: URL) -> String {
        guard let host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host, !host.isEmpty else {
            return url.absoluteString
        }
        return withoutWWW(host.lowercased())
    }

    /// Versão `https` de um endereço `http`; um `https` volta como está e o que não é da web, `nil`.
    public static func secureVariant(of url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false), isWebAddress(components) else {
            return nil
        }
        if components.scheme?.lowercased() == "https" { return url }
        components.scheme = "https"
        return components.url
    }

    private static func isWebAddress(_ components: URLComponents) -> Bool {
        guard let scheme = components.scheme?.lowercased(), webSchemes.contains(scheme) else { return false }
        return components.host?.isEmpty == false
    }

    private static func isTracking(_ name: String) -> Bool {
        let name = name.lowercased()
        return name.hasPrefix("utm_") || trackingParameters.contains(name)
    }

    /// Tira o `www.` do começo de um host já em minúsculas.
    private static func withoutWWW(_ host: String) -> String {
        guard host.hasPrefix("www."), host.count > 4 else { return host }
        return String(host.dropFirst(4))
    }
}
