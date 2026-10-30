import Foundation

/// Quais endereços vindos de conteúdo importado (lembrete, música, link dentro de PDF) podem ser entregues ao sistema.
///
/// Um `.mural` de outra pessoa não é confiável: um clique não pode abrir `file:`, `smb:`, `shortcuts:` nem esquemas de apps.
public enum ExternalURLPolicy {
    /// Esquemas de fora da web que o sistema pode abrir: e-mail, ligação, mensagem e FaceTime.
    public static let systemSchemes: Set<String> = ["mailto", "tel", "sms", "facetime", "facetime-audio"]

    private static let appleMusicHosts: Set<String> = ["music.apple.com", "itunes.apple.com", "geo.music.apple.com"]

    /// Indica se o endereço pode ser aberto: `http`/`https` com host, ou um dos `systemSchemes`.
    public static func allowsOpening(_ url: URL) -> Bool {
        if WebLink.isWeb(url) { return true }
        guard let scheme = url.scheme?.lowercased() else { return false }
        return systemSchemes.contains(scheme)
    }

    /// Indica se o endereço é um link `https` do Apple Music (host exato, sem diferenciar maiúsculas).
    public static func isAppleMusicWebLink(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "https",
            let host = components.host?.lowercased()
        else { return false }
        return appleMusicHosts.contains(host)
    }
}
