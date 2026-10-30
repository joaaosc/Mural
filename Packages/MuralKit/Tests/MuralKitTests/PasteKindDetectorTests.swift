import Foundation
import Testing

@testable import MuralKit

@Suite("Detector do jeito de colar texto")
struct PasteKindDetectorTests {
    private func detect(_ text: String, embeds: Bool = false, images: Bool = false) -> PasteKindSuggestion {
        PasteKindDetector.detect(text: text, hasEmbeds: embeds, hasImages: images)
    }

    private let long = String(repeating: "palavra ", count: 40)

    @Test("Texto em branco não oferece nada")
    func blank() {
        #expect(detect("  \n ").options.isEmpty)
        #expect(detect("").options.isEmpty)
    }

    @Test("Endereços sugerem links, com a contagem; o texto e o post-it continuam oferecidos")
    func links() {
        let result = detect("https://example.com/a\nhttps://example.com/b")
        #expect(result.suggested == .links(count: 2))
        #expect(result.options == [.links(count: 2), .text, .sticky])
        #expect(result.unavailable.isEmpty)
        #expect(PasteKind.links(count: 2).itemKind == nil)
    }

    @Test("Texto com cara de lista sugere lista, inclusive a numerada")
    func checklist() {
        for text in ["- a\n- b", "1. a\n2. b", "[ ] a\n[x] b"] {
            let result = detect(text)
            #expect(result.suggested == .checklist, "\(text)")
            #expect(result.options == [.checklist, .text, .sticky])
        }
    }

    @Test("Texto curto sugere post-it e o longo, nota")
    func stickyAndText() {
        let short = detect("Ligar para o marceneiro")
        #expect(short.suggested == .sticky && short.options == [.sticky, .text])
        let longer = detect(long)
        #expect(longer.suggested == .text && longer.options == [.text, .sticky])
        #expect(PasteKind.sticky.itemKind == .sticky && PasteKind.text.itemKind == .text && PasteKind.checklist.itemKind == .checklist)
    }

    @Test("Com cartões ou imagens, post-it, lista e links ficam indisponíveis, com o motivo, e a sugestão cai na nota")
    func vetoes() {
        for (embeds, images) in [(true, false), (false, true), (true, true)] {
            let sticky = detect("Ligar para o marceneiro", embeds: embeds, images: images)
            #expect(sticky.suggested == .text)
            #expect(sticky.unavailable == [.sticky: "Sticker não guarda imagens nem cartões"])

            let links = detect("https://example.com/a", embeds: embeds, images: images)
            #expect(links.suggested == .text)
            #expect(links.unavailable[.links(count: 1)] == "Cartões de link não guardam imagens nem cartões")
            #expect(links.unavailable[.sticky] == "Sticker não guarda imagens nem cartões")

            let list = detect("- a\n- b", embeds: embeds, images: images)
            #expect(list.suggested == .text)
            #expect(list.unavailable[.checklist] == "Lista não guarda imagens nem cartões")
            #expect(list.unavailable[.sticky] != nil)
        }
    }

    @Test("A sugestão sempre está entre as opções e nunca é um tipo indisponível")
    func suggestedIsAlwaysOfferedAndAvailable() {
        let texts = ["Oi", "- a\n- b", "1. a\n2. b", "https://example.com", long, "https://example.com\nhttps://example.org"]
        for text in texts {
            for (embeds, images) in [(false, false), (true, false), (false, true), (true, true)] {
                let result = detect(text, embeds: embeds, images: images)
                #expect(result.options.contains(result.suggested), "\(text) \(embeds) \(images)")
                #expect(result.unavailable[result.suggested] == nil, "\(text) \(embeds) \(images)")
            }
        }
    }
}
