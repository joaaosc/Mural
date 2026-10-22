import AppKit
import MuralKit
import Testing

@testable import Mural

/// Ordem das fontes e junção dos repetidos. Cada teste usa uma área de transferência privada.
@MainActor
struct LinkPasteboardReaderTests {
    private static let urlName = NSPasteboard.PasteboardType("public.url-name")
    private static let bookmarkList = NSPasteboard.PasteboardType("com.apple.Safari.bookmarkDictionaryList")
    private static let urlsWithTitles = NSPasteboard.PasteboardType("WebURLsWithTitlesPboardType")

    private func address(_ text: String) throws -> URL {
        try #require(URL(string: text))
    }

    private static func addressItem(_ address: String, name: String? = nil, text: String? = nil) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(address, forType: .URL)
        if let name { item.setString(name, forType: urlName) }
        if let text { item.setString(text, forType: .string) }
        return item
    }

    private static func bookmarkItem(_ entries: [[String: Any]]) throws -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setData(try PropertyListSerialization.data(fromPropertyList: entries, format: .binary, options: 0), forType: bookmarkList)
        return item
    }

    // MARK: Ordem

    @Test("Ordem: favoritos do Safari, endereços com títulos, itens com public.url e texto")
    func sourcesAreReadInOrder() throws {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        fixture.write(
            Self.addressItem("https://b.example/pagina", name: "B", text: "https://f.example/texto"),
            try Self.bookmarkItem([["URLString": "https://a.example/pagina", "URIDictionary": ["title": "A"]]]))
        fixture.addLegacy([["https://c.example/pagina"], ["C"]], forType: Self.urlsWithTitles)

        let drafts = LinkPasteboardReader.drafts(from: fixture.pasteboard)

        #expect(
            drafts.map(\.url.absoluteString) == [
                "https://a.example/pagina", "https://c.example/pagina", "https://b.example/pagina", "https://f.example/texto",
            ])
        #expect(drafts.map(\.title) == ["A", "C", "B", nil])
    }

    @Test("Área vazia, arquivos ou texto comum não geram links")
    func nothingToRead() {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        #expect(LinkPasteboardReader.drafts(from: fixture.pasteboard).isEmpty)

        fixture.pasteboard.setString("só uma anotação, https://a.example no meio", forType: .string)
        #expect(LinkPasteboardReader.drafts(from: fixture.pasteboard).isEmpty)

        fixture.pasteboard.clearContents()
        fixture.pasteboard.writeObjects([URL(fileURLWithPath: "/tmp/arquivo.png") as NSURL])
        #expect(LinkPasteboardReader.drafts(from: fixture.pasteboard).isEmpty)
    }

    // MARK: Repetidos

    @Test("De duas leituras da mesma página fica a mais rica, na posição da primeira")
    func richerDraftReplacesInPlace() throws {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        fixture.write(
            Self.addressItem("https://outra.example/pagina"), Self.addressItem("https://www.a.example/pagina/", name: "Título do item"))
        // Esta lista é lida primeiro e não traz título: o item com o nome da página a substitui, no mesmo lugar.
        fixture.addLegacy([["https://a.example/pagina#topo"], [""]], forType: Self.urlsWithTitles)

        let drafts = LinkPasteboardReader.drafts(from: fixture.pasteboard)

        #expect(drafts.map(\.url.absoluteString) == ["https://www.a.example/pagina/", "https://outra.example/pagina"])
        #expect(drafts.map(\.title) == ["Título do item", nil])
    }

    @Test("Em empate ganha quem veio primeiro")
    func tieKeepsTheFirst() throws {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        fixture.write(Self.addressItem("https://a.example/pagina", name: "Segundo", text: "https://a.example/pagina"))
        fixture.addLegacy([["https://a.example/pagina"], ["Primeiro"]], forType: Self.urlsWithTitles)

        let drafts = LinkPasteboardReader.drafts(from: fixture.pasteboard)

        #expect(drafts.map(\.title) == ["Primeiro"])
    }

    @Test("Título, resumo e imagem contam como riqueza, e texto em branco não conta")
    func richnessCountsTitleSummaryAndImage() throws {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        // Mesma página em três favoritos: só título em branco, título e resumo, título resumo e imagem.
        fixture.write(
            try Self.bookmarkItem([
                ["URLString": "https://a.example/pagina", "URIDictionary": ["title": "  "]],
                ["URLString": "https://a.example/pagina/", "URIDictionary": ["title": "Com título"], "previewText": "Com resumo"],
                [
                    "URLString": "https://www.a.example/pagina", "URIDictionary": ["title": "Completo"], "previewText": "Resumo",
                    "imageURL": "https://cdn.example/capa.jpg",
                ],
                ["URLString": "https://a.example/pagina#fim", "URIDictionary": ["title": "Outro completo"], "previewText": "Resumo 2"],
            ]))

        let drafts = LinkPasteboardReader.drafts(from: fixture.pasteboard)

        #expect(drafts.map(\.title) == ["Completo"])
        #expect(drafts.first?.imageURL?.absoluteString == "https://cdn.example/capa.jpg")
    }
}
