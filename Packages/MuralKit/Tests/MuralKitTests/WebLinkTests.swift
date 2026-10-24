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
            "ftp://apple.com/arquivo.zip", "file:///Users/test-user/nota.txt", "mailto:someone@example.com",
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
            ("ftp://apple.com", false), ("file:///Users/test-user/nota.txt", false), ("mailto:someone@example.com", false),
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
        #expect(try key("mailto:someone@example.com") == "mailto:someone@example.com")
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
            ("mailto:someone@example.com", "mailto:someone@example.com"),
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
            "ftp://apple.com", "file:///Users/test-user/nota.txt", "mailto:someone@example.com", "javascript:alert(1)", "http://", "/caminho",
        ])
    func noSecureVariant(text: String) throws {
        #expect(WebLink.secureVariant(of: try url(text)) == nil)
    }

    // MARK: urls(inText:)

    private func addresses(inText text: String) -> [String] {
        WebLink.urls(inText: text).map(\.absoluteString)
    }

    @Test("Um endereço por linha, na ordem em que aparecem")
    func listsOneAddressPerLine() {
        #expect(addresses(inText: "https://apple.com") == ["https://apple.com"])
        #expect(
            addresses(inText: "https://apple.com/mac\nhttp://swift.org\nwww.example.com/a?x=1")
                == ["https://apple.com/mac", "http://swift.org", "https://www.example.com/a?x=1"])
    }

    @Test(
        "Linhas em branco, espaços nas pontas e qualquer quebra de linha são ignorados",
        arguments: [
            "\n\nhttps://apple.com\n\nhttps://swift.org\n\n",
            "  https://apple.com  \n\thttps://swift.org\t",
            "https://apple.com\r\nhttps://swift.org\r\n",
            "https://apple.com\rhttps://swift.org",
            "https://apple.com\u{2028}https://swift.org",
            "https://apple.com\n \t \nhttps://swift.org",
        ])
    func ignoresBlankLinesAndPadding(text: String) {
        #expect(addresses(inText: text) == ["https://apple.com", "https://swift.org"])
    }

    @Test(
        "Um par de <…>, aspas duplas ou aspas simples em volta da linha é retirado",
        arguments: [
            ("<https://apple.com/mac>", "https://apple.com/mac"),
            ("\"https://apple.com/mac\"", "https://apple.com/mac"),
            ("'https://apple.com/mac'", "https://apple.com/mac"),
            ("  <https://apple.com/mac>  \n", "https://apple.com/mac"),
            ("<www.apple.com/mac>", "https://www.apple.com/mac"),
        ])
    func removesWrappers(text: String, expected: String) {
        #expect(addresses(inText: text) == [expected])
    }

    @Test("Cada linha tem o seu invólucro")
    func eachLineHasItsOwnWrapper() {
        #expect(
            addresses(inText: "<https://apple.com>\n\"https://swift.org\"\n'https://example.com'\nhttps://example.org")
                == ["https://apple.com", "https://swift.org", "https://example.com", "https://example.org"])
    }

    @Test(
        "Invólucro que não casa, repetido ou vazio não vale",
        arguments: [
            "<https://apple.com", "https://apple.com>", "\"https://apple.com'", "'https://apple.com\"", "<<https://apple.com>>",
            "\"<https://apple.com>\"", "<\"https://apple.com\">", "``https://apple.com``", "[https://apple.com]", "(https://apple.com)",
            "<>", "\"\"", "''", "\"", "<",
        ])
    func rejectsBrokenWrappers(text: String) {
        #expect(WebLink.urls(inText: text).isEmpty)
    }

    @Test(
        "Uma linha que não é só um endereço invalida o texto todo",
        arguments: [
            "https://apple.com\nveja isto", "veja isto\nhttps://apple.com", "https://apple.com\nhttps://swift.org depois",
            "https://apple.com\n- https://swift.org", "https://apple.com\napple.com", "https://apple.com\nftp://apple.com/arquivo",
            "https://apple.com\nmailto:someone@example.com", "https://apple.com\njavascript:alert(1)", "https://apple.com\nhttps://",
            "https://apple.com\nhttps://swift.org https://example.com",
        ])
    func oneBadLineRejectsEverything(text: String) {
        #expect(WebLink.urls(inText: text).isEmpty)
    }

    @Test(
        "Um parágrafo ou uma frase com um endereço no meio continua sendo texto",
        arguments: [
            "Veja https://apple.com/mac depois", "https://apple.com é o site", "Leia: https://apple.com",
            "Anotações da reunião\nhttps://apple.com/mac\nFim", "https://apple.com https://swift.org",
            "Primeiro parágrafo.\n\nSegundo, com https://swift.org no meio.",
        ])
    func proseStaysText(text: String) {
        #expect(WebLink.urls(inText: text).isEmpty)
    }

    @Test(
        "Texto sem nenhum endereço devolve vazio",
        arguments: [
            "", "   ", "\n\n", " \t\r\n ", "apple.com", "texto qualquer", "ftp://apple.com", "mailto:someone@example.com",
            "file:///Users/test-user/a.txt",
        ])
    func nothingToList(text: String) {
        #expect(WebLink.urls(inText: text).isEmpty)
    }

    @Test("Endereços repetidos são todos devolvidos: quem importa é que junta os repetidos")
    func keepsRepeatedAddresses() {
        #expect(addresses(inText: "https://apple.com\nhttps://apple.com") == ["https://apple.com", "https://apple.com"])
    }

    @Test("Até 500 linhas não vazias; com mais, o texto deixa de ser tratado como lista")
    func lineLimit() {
        let lines = (1...501).map { "https://example.com/pagina-\($0)" }

        #expect(WebLink.urls(inText: lines.prefix(500).joined(separator: "\n")).count == 500)
        #expect(WebLink.urls(inText: lines.joined(separator: "\n")).isEmpty)
        #expect(WebLink.urls(inText: lines.prefix(499).joined(separator: "\n")).count == 499)
        // Linhas em branco não contam para o limite.
        #expect(WebLink.urls(inText: lines.prefix(500).joined(separator: "\n\n")).count == 500)
    }
}
