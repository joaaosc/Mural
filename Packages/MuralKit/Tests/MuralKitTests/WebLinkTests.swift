import Foundation
import Testing

@testable import MuralKit

@Suite("Endereços da web")
struct WebLinkTests {
    private func url(_ text: String) throws -> URL {
        try #require(URL(string: text))
    }

    private func key(_ text: String) throws -> String {
        WebLink.dedupeKey(for: try url(text))
    }

    // MARK: url(from:)

    @Test(
        "Texto com um endereço da web vira URL",
        arguments: [
            ("https://apple.com", "https://apple.com"),
            ("http://example.com/a/b?x=1&y=2#topo", "http://example.com/a/b?x=1&y=2#topo"),
            ("  https://apple.com/iphone\n", "https://apple.com/iphone"),
            ("\n\t http://apple.com \t\n", "http://apple.com"),
            ("HTTPS://Apple.com/Mac", "HTTPS://Apple.com/Mac"),
            ("www.apple.com", "https://www.apple.com"),
            ("www.apple.com/mac?x=1#topo", "https://www.apple.com/mac?x=1#topo"),
            ("  WWW.apple.com\n", "https://WWW.apple.com"),
            ("http://localhost:3000/painel", "http://localhost:3000/painel"),
            ("http://192.168.0.10:8080", "http://192.168.0.10:8080"),
            ("https://pt.wikipedia.org/wiki/São_Paulo", "https://pt.wikipedia.org/wiki/S%C3%A3o_Paulo"),
            ("https://pt.wikipedia.org/wiki/S%C3%A3o_Paulo", "https://pt.wikipedia.org/wiki/S%C3%A3o_Paulo"),
        ])
    func acceptsWebAddresses(text: String, expected: String) {
        #expect(WebLink.url(from: text)?.absoluteString == expected)
    }

    @Test(
        "Outros esquemas, palavras soltas e endereço sem host não viram link",
        arguments: [
            "", "   \n\t", "apple.com", "apple.com/mac", "localhost:3000", "www", "www.", "  www.  ", "//apple.com",
            "ftp://apple.com/arquivo.zip", "file:///Users/joao/nota.txt", "mailto:alguem@apple.com",
            "javascript:alert(1)", "JAVASCRIPT:alert(1)", "data:text/html,<b>oi</b>", "tel:+5521999999999",
            "https://", "http://", "https:///caminho", "https://:8080", "http:apple.com", "Apple Park",
        ])
    func rejectsOtherSchemesAndBareWords(text: String) {
        #expect(WebLink.url(from: text) == nil)
    }

    @Test(
        "Texto com espaço ou quebra de linha no meio não vira link, em qualquer parte do endereço",
        arguments: [
            "veja https://apple.com", "https://apple.com e mais", "https://apple .com",
            "https://apple.com https://example.com", "https://apple.com\nhttps://example.com",
            "https://apple.com/mac iphone", "https://apple.com/mac?x=1 y=2", "https://apple.com/mac#topo fim",
            "https://apple.com/mac\nhttps://apple.com/iphone", "https://apple.com/mac\thttps://apple.com/iphone",
            "www.apple.com/mac iphone", "www.apple.com\nwww.example.com",
        ])
    func rejectsInnerWhitespace(text: String) {
        #expect(WebLink.url(from: text) == nil)
    }

    // MARK: isWeb

    @Test(
        "Só http e https com host contam como web",
        arguments: [
            ("https://apple.com", true), ("http://apple.com/a?b=1", true), ("HTTPS://APPLE.COM", true), ("http://localhost:3000", true),
            ("ftp://apple.com", false), ("file:///Users/joao/nota.txt", false), ("mailto:alguem@apple.com", false),
            ("javascript:alert(1)", false), ("https://", false), ("http:///caminho", false), ("/caminho/relativo", false),
            ("apple.com", false),
        ])
    func isWeb(text: String, expected: Bool) throws {
        #expect(WebLink.isWeb(try url(text)) == expected)
    }

    // MARK: dedupeKey

    @Test(
        "Escritas diferentes da mesma página têm a mesma chave",
        arguments: [
            ("http e https", ["http://apple.com/mac", "https://apple.com/mac"]),
            ("com e sem www", ["https://www.apple.com/mac", "https://apple.com/mac", "http://www.apple.com/mac"]),
            ("host em maiúsculas", ["https://APPLE.com/mac", "https://Apple.COM/mac", "HTTPS://apple.com/mac"]),
            ("barra final", ["https://apple.com/mac", "https://apple.com/mac/"]),
            ("raiz com e sem barra", ["https://apple.com", "https://apple.com/", "http://www.apple.com/"]),
            ("fragmento", ["https://apple.com/mac#topo", "https://apple.com/mac", "https://apple.com/mac/#outro"]),
            ("porta padrão", ["https://apple.com:443/mac", "http://apple.com:80/mac", "https://apple.com/mac"]),
            (
                "rastreamento",
                [
                    "https://apple.com/mac", "https://apple.com/mac?utm_source=a&utm_medium=b", "https://apple.com/mac?UTM_Campaign=x",
                    "https://apple.com/mac?fbclid=1", "https://apple.com/mac?gclid=2&mc_cid=3&mc_eid=4",
                ]
            ),
            (
                "ordem dos parâmetros",
                ["https://apple.com/s?a=1&b=2", "https://apple.com/s?b=2&a=1", "https://apple.com/s?b=2&utm_term=x&a=1#y"]
            ),
        ])
    func equivalentAddressesShareKey(name: String, addresses: [String]) throws {
        let keys = try addresses.map(key)
        #expect(Set(keys).count == 1, "\(name): \(keys)")
    }

    @Test(
        "Páginas diferentes têm chaves diferentes",
        arguments: [
            ("https://apple.com/mac", "https://apple.com/iphone"),
            ("https://apple.com/Mac", "https://apple.com/mac"),
            ("https://apple.com/mac", "https://apple.com/mac/ipad"),
            ("https://apple.com/s?q=1", "https://apple.com/s?q=2"),
            ("https://apple.com/s", "https://apple.com/s?q=1"),
            ("https://apple.com/s?q=1&utm_source=a", "https://apple.com/s"),
            ("https://apple.com:8080/mac", "https://apple.com/mac"),
            ("https://support.apple.com/mac", "https://apple.com/mac"),
        ])
    func differentAddressesHaveDifferentKeys(first: String, second: String) throws {
        #expect(try key(first) != key(second))
    }

    @Test("A chave junta host, porta fora do padrão, caminho e parâmetros em ordem")
    func keyFormat() throws {
        #expect(try key("https://www.Apple.com:443/Mac/?utm_source=a&b=2&a=1#topo") == "apple.com/Mac?a=1&b=2")
        #expect(try key("http://apple.com:8080") == "apple.com:8080")
        #expect(try key("https://apple.com/") == "apple.com")
    }

    @Test("Endereço que não é da web vira o próprio texto")
    func keyOfNonWebAddress() throws {
        #expect(try key("mailto:alguem@apple.com") == "mailto:alguem@apple.com")
        #expect(try key("https://") == "https://")
    }

    // MARK: displayHost

    @Test(
        "O host aparece em minúsculas e sem www; sem host, aparece o endereço",
        arguments: [
            ("https://www.apple.com/mac", "apple.com"),
            ("https://apple.com", "apple.com"),
            ("http://WWW.Apple.COM/Mac", "apple.com"),
            ("https://support.apple.com", "support.apple.com"),
            ("http://localhost:3000/painel", "localhost"),
            ("mailto:alguem@apple.com", "mailto:alguem@apple.com"),
            ("/caminho/relativo", "/caminho/relativo"),
        ])
    func displayHost(text: String, expected: String) throws {
        #expect(WebLink.displayHost(of: try url(text)) == expected)
    }

    // MARK: secureVariant

    @Test(
        "http vira https e o resto do endereço fica igual",
        arguments: [
            ("http://apple.com", "https://apple.com"),
            ("http://apple.com:8080/mac?x=1#topo", "https://apple.com:8080/mac?x=1#topo"),
            ("HTTP://Apple.com/Mac", "https://Apple.com/Mac"),
        ])
    func upgradesHTTP(text: String, expected: String) throws {
        #expect(WebLink.secureVariant(of: try url(text))?.absoluteString == expected)
    }

    @Test("https devolve o próprio endereço")
    func keepsHTTPS() throws {
        let secure = try url("https://apple.com/mac?x=1")
        #expect(WebLink.secureVariant(of: secure) == secure)
    }

    @Test(
        "Outros esquemas e endereços sem host não têm versão segura",
        arguments: [
            "ftp://apple.com", "file:///Users/joao/nota.txt", "mailto:alguem@apple.com", "javascript:alert(1)", "http://", "/caminho",
        ])
    func noSecureVariant(text: String) throws {
        #expect(WebLink.secureVariant(of: try url(text)) == nil)
    }
}
