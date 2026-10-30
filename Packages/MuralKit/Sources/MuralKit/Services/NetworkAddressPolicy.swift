import Darwin
import Foundation

/// Decide se um endereço pode ser buscado automaticamente: só páginas da internet pública. Recusa a rede local
/// e o próprio Mac, para que um mural vindo de fora não use o app para sondar o que está atrás do roteador.
public enum NetworkAddressPolicy {
    public static func isPublicWebAddress(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            var host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty
        else { return false }
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        // Ponto final de nome absoluto ("localhost.").
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty else { return false }

        if let v4 = parseIPv4(host) { return isPublic(v4: v4) }
        if let v6 = parseIPv6(host) { return isPublic(v6: v6) }
        // Forma numérica que o resolvedor aceitaria (0x7f.1, 2130706433): não é nome público de verdade.
        if host.allSatisfy({ $0.isHexDigit || $0 == "." || $0 == "x" }), host.first?.isNumber == true { return false }

        guard host.contains(".") else { return false }
        for suffix in blockedSuffixes where host == suffix || host.hasSuffix("." + suffix) { return false }
        return true
    }

    private static let blockedSuffixes = ["localhost", "local", "internal", "lan", "home.arpa"]

    private static func parseIPv4(_ text: String) -> [UInt8]? {
        var address = in_addr()
        guard inet_pton(AF_INET, text, &address) == 1 else { return nil }
        return withUnsafeBytes(of: &address) { Array($0) }
    }

    private static func parseIPv6(_ text: String) -> [UInt8]? {
        // Escopo ("fe80::1%en0") não faz parte do endereço.
        let bare = text.split(separator: "%", maxSplits: 1).first.map(String.init) ?? text
        var address = in6_addr()
        guard inet_pton(AF_INET6, bare, &address) == 1 else { return nil }
        return withUnsafeBytes(of: &address) { Array($0) }
    }

    private static func isPublic(v4 b: [UInt8]) -> Bool {
        switch (b[0], b[1]) {
        case (0, _), (10, _), (127, _): return false
        case (100, 64...127): return false
        case (169, 254): return false
        case (172, 16...31): return false
        case (192, 168): return false
        case (224..., _): return false
        default: return true
        }
    }

    private static func isPublic(v6 b: [UInt8]) -> Bool {
        // :: e ::1
        if b[0..<15].allSatisfy({ $0 == 0 }), b[15] <= 1 { return false }
        // fc00::/7, fe80::/10, ff00::/8
        if b[0] & 0xFE == 0xFC || b[0] == 0xFF { return false }
        if b[0] == 0xFE, b[1] & 0xC0 == 0x80 { return false }
        // IPv4 mapeado (::ffff:a.b.c.d) e compatível (::a.b.c.d): vale a regra do IPv4 embutido.
        if b[0..<10].allSatisfy({ $0 == 0 }), b[10] == 0xFF, b[11] == 0xFF { return isPublic(v4: Array(b[12..<16])) }
        if b[0..<12].allSatisfy({ $0 == 0 }) { return isPublic(v4: Array(b[12..<16])) }
        return true
    }
}
