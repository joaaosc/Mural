import Foundation
import Testing

@testable import MuralKit

private let sampleHosts = [
    "apple.com", "1password.com", "ñandu.org", "github.com", "developer.apple.com", "wikipedia.org",
    "pt.wikipedia.org", "youtube.com", "nytimes.com", "figma.com", "notion.so", "dribbble.com",
    "behance.net", "medium.com", "are.na", "pinterest.com", "example.com", "example.org", "localhost",
    "192.168.0.10", "vimeo.com", "spotify.com", "theverge.com", "arstechnica.com", "stackoverflow.com",
    "reddit.com", "news.ycombinator.com", "linear.app", "vercel.com", "uol.com.br", "globo.com", "folha.uol.com.br",
]

@Suite("Monograma de links")
struct LinkMonogramTests {
    // MARK: Letra

    @Test(
        "A letra é o primeiro caractere alfanumérico do host, em maiúscula",
        arguments: [
            ("apple.com", "A"), ("1password.com", "1"), ("ñandu.org", "Ñ"), ("école.fr", "É"), ("Apple.com", "A"),
            ("github.com", "G"), ("192.168.0.10", "1"), ("日本.jp", "日"), ("ßtest.de", "S"),
        ])
    func letterIsFirstAlphanumericUppercased(host: String, expected: String) {
        #expect(LinkMonogram.letter(for: host) == expected)
    }

    @Test(
        "Pontuação no começo do host é pulada",
        arguments: [("-apple.com", "A"), (".1password.com", "1"), ("[::1]", "1"), ("..._x", "X")])
    func letterSkipsLeadingPunctuation(host: String, expected: String) {
        #expect(LinkMonogram.letter(for: host) == expected)
    }

    @Test("Sem nenhum caractere alfanumérico, a letra é um ponto central", arguments: ["", " ", "...", "-_-", "[::]"])
    func letterFallsBackToBullet(host: String) {
        #expect(LinkMonogram.letter(for: host) == "•")
    }

    @Test("A letra tem sempre um único caractere", arguments: sampleHosts + ["ßtest.de", "ǆ.example", "", "..."])
    func letterIsSingleCharacter(host: String) {
        #expect(LinkMonogram.letter(for: host).count == 1)
    }

    // MARK: Matiz

    @Test("O mesmo host dá sempre o mesmo matiz", arguments: sampleHosts)
    func hueIsRepeatable(host: String) {
        #expect(LinkMonogram.hue(for: host) == LinkMonogram.hue(for: host))
    }

    /// Valores fixos: um hash que mude a cada execução (como `hashValue`) ou um algoritmo trocado sem querer
    /// mudaria a cor que cada site já tem nos cartões.
    @Test("O matiz é o FNV-1a de 32 bits do host, estável entre execuções")
    func hueMatchesFNV1a() {
        #expect(LinkMonogram.hue(for: "apple.com") == 3_197_224_656.0 / 4_294_967_296.0)
        #expect(LinkMonogram.hue(for: "1password.com") == 481_790_298.0 / 4_294_967_296.0)
        #expect(LinkMonogram.hue(for: "ñandu.org") == 2_261_603_293.0 / 4_294_967_296.0)
        #expect(LinkMonogram.hue(for: "") == 2_166_136_261.0 / 4_294_967_296.0)
    }

    @Test("O matiz fica de 0 (incluso) a 1 (excluso)", arguments: sampleHosts + ["", " ", "•", "xn--nandu-sza.org", "a", "ÿ"])
    func hueIsInRange(host: String) {
        let hue = LinkMonogram.hue(for: host)
        #expect(hue >= 0 && hue < 1)
    }

    @Test("Maiúsculas e minúsculas no host não mudam o matiz")
    func hueIgnoresCase() {
        #expect(LinkMonogram.hue(for: "Apple.COM") == LinkMonogram.hue(for: "apple.com"))
        #expect(LinkMonogram.hue(for: "ÑANDU.org") == LinkMonogram.hue(for: "ñandu.org"))
    }

    @Test("Hosts diferentes costumam dar matizes diferentes")
    func hueSpreadsAcrossHosts() {
        let hues = sampleHosts.map(LinkMonogram.hue(for:))
        #expect(Set(hues).count == hues.count, "dois hosts do exemplo deram exatamente o mesmo matiz")

        // 32 hosts espalhados em 12 faixas de 30 graus: um hash ruim juntaria quase todos numa faixa só.
        let sectors = Set(hues.map { Int($0 * 12) })
        #expect(sectors.count >= 8, "só \(sectors.count) das 12 faixas de cor foram usadas")
    }
}
