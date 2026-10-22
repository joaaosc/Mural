import AppKit
import LinkPresentation
import MuralKit
import Testing

@testable import Mural

/// ⌘V com links. Todos os testes usam uma área de transferência privada: a geral é do usuário e nunca é tocada.
@MainActor
struct PasteboardImporterLinkTests {
    private static let urlName = NSPasteboard.PasteboardType("public.url-name")
    private static let bookmarkList = NSPasteboard.PasteboardType("com.apple.Safari.bookmarkDictionaryList")
    private static let linkMetadata = NSPasteboard.PasteboardType("com.apple.linkpresentation.metadata")
    private static let urlsWithTitles = NSPasteboard.PasteboardType("WebURLsWithTitlesPboardType")

    // MARK: Endereço copiado

    @Test("Endereço com o nome da página vira um cartão de link com aquele título")
    func addressWithNameBecomesLink() async throws {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        fixture.write(Self.addressItem("https://www.apple.com/br/mac/", name: "Mac – Apple (BR)"))

        await fixture.paste()

        #expect(fixture.model.board.items.count == 1)
        let item = try #require(fixture.model.board.items.first)
        #expect(item.kind == .link)
        #expect(item.title == "Mac – Apple (BR)")
        #expect(item.link?.url.absoluteString == "https://www.apple.com/br/mac/")
        #expect(item.link?.preview == .pending)
        #expect(fixture.model.lastError == nil)
    }

    @Test("Sem o nome da página, o título vem dos metadados do link arquivados pelo Safari")
    func titleComesFromLinkMetadata() async throws {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        let item = Self.addressItem("https://example.com/artigo")
        item.setData(try Self.metadataData(title: "Título dos metadados", url: "https://example.com/artigo"), forType: Self.linkMetadata)
        fixture.write(item)

        await fixture.paste()

        #expect(fixture.model.board.items.count == 1)
        #expect(fixture.links.first?.title == "Título dos metadados")
    }

    @Test("O nome da página vale mais que os metadados do link")
    func pageNameBeatsLinkMetadata() async throws {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        let item = Self.addressItem("https://example.com/artigo", name: "Nome da página")
        item.setData(try Self.metadataData(title: "Título dos metadados", url: "https://example.com/artigo"), forType: Self.linkMetadata)
        fixture.write(item)

        await fixture.paste()

        #expect(fixture.links.map(\.title) == ["Nome da página"])
    }

    @Test("Metadados ilegíveis ou sem título deixam o cartão com o host")
    func unreadableMetadataFallsBackToHost() async throws {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        let broken = Self.addressItem("https://www.example.com/a")
        broken.setData(Data("isto não é um arquivo arquivado".utf8), forType: Self.linkMetadata)
        let untitled = Self.addressItem("https://www.example.org/b")
        untitled.setData(try Self.metadataData(title: nil, url: "https://www.example.org/b"), forType: Self.linkMetadata)
        fixture.write(broken, untitled)

        await fixture.paste()

        #expect(fixture.links.map(\.title) == ["example.com", "example.org"])
    }

    @Test("Vários endereços copiados juntos viram um cartão cada, na ordem")
    func severalAddressItems() async {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        fixture.write(
            Self.addressItem("https://apple.com/mac", name: "Mac"), Self.addressItem("https://swift.org", name: "Swift"),
            Self.addressItem("https://apple.com/mac/", name: "Mac de novo"))

        await fixture.paste()

        #expect(fixture.links.map(\.title) == ["Mac", "Swift"])
    }

    @Test("Dentro de uma pasta aberta o link entra na pasta")
    func linkGoesIntoTheOpenFolder() async throws {
        let folder = BoardItem(kind: .folder, title: "Pasta")
        let fixture = LinkImportFixture(items: [folder])
        defer { fixture.tearDown() }
        fixture.write(Self.addressItem("https://example.com/na-pasta", name: "Na pasta"))

        await fixture.paste(into: folder.id)

        let link = try #require(fixture.links.first)
        #expect(link.parentID == folder.id)
        #expect(fixture.model.rootItems.map(\.id) == [folder.id])
    }

    // MARK: Texto

    @Test(
        "Texto que é só um endereço vira cartão de link",
        arguments: [
            ("https://apple.com/mac", "https://apple.com/mac"), ("  https://apple.com/mac\n", "https://apple.com/mac"),
            ("<https://apple.com/mac>", "https://apple.com/mac"), ("www.apple.com/mac", "https://www.apple.com/mac"),
        ])
    func addressTextBecomesLink(text: String, expected: String) async throws {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        fixture.pasteboard.setString(text, forType: .string)

        await fixture.paste()

        #expect(fixture.model.board.items.count == 1)
        let item = try #require(fixture.links.first)
        #expect(item.link?.url.absoluteString == expected)
        #expect(item.title == "apple.com")
    }

    @Test("Três endereços em linhas viram três links, na ordem")
    func addressesInLinesBecomeLinks() async {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        fixture.pasteboard.setString("https://apple.com/mac\nhttps://swift.org\n\nhttps://example.com/pagina?x=1\n", forType: .string)

        await fixture.paste()

        #expect(fixture.model.board.items.count == 3)
        #expect(
            fixture.links.compactMap(\.link?.url.absoluteString)
                == ["https://apple.com/mac", "https://swift.org", "https://example.com/pagina?x=1"])
    }

    @Test("Frase com um endereço no meio continua sendo post-it, e parágrafo longo, nota")
    func sentenceWithAddressStaysNote() async throws {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        let sentence = "Veja https://apple.com/mac depois"
        fixture.pasteboard.setString(sentence, forType: .string)

        await fixture.paste()

        let sticky = try #require(fixture.model.board.items.first)
        #expect(fixture.model.board.items.count == 1)
        #expect(sticky.kind == .sticky)
        #expect(sticky.text == sentence)

        let paragraph = String(repeating: "Texto de uma reunião sobre o site https://apple.com/mac e outros assuntos. ", count: 4)
        fixture.pasteboard.clearContents()
        fixture.pasteboard.setString(paragraph, forType: .string)

        await fixture.paste()

        #expect(fixture.model.board.items.count == 2)
        #expect(fixture.model.board.items.last?.kind == .text)
        #expect(fixture.links.isEmpty)
    }

    @Test("Uma linha que não é endereço faz o texto todo continuar sendo texto")
    func oneBadLineKeepsTheText() async {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        fixture.pasteboard.setString("https://apple.com/mac\nhttps://swift.org\nlembrar de ler depois", forType: .string)

        await fixture.paste()

        #expect(fixture.model.board.items.count == 1)
        #expect(fixture.links.isEmpty)
    }

    @Test("Endereço que não é da web continua sendo texto")
    func nonWebAddressStaysText() async throws {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        fixture.write(Self.addressItem("mailto:alguem@apple.com"))

        await fixture.paste()

        let item = try #require(fixture.model.board.items.first)
        #expect(fixture.model.board.items.count == 1)
        #expect(item.kind == .sticky)
        #expect(item.text == "mailto:alguem@apple.com")
    }

    // MARK: Imagem e PDF vêm antes

    @Test("Imagem copiada junto com o endereço (Copiar Imagem do Safari) continua virando imagem", arguments: ["tiff", "jpeg", "png"])
    func imageWithAddressStaysImage(format: String) async throws {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        let item = Self.addressItem("https://example.com/fotos/praia", name: "Praia")
        switch format {
        case "tiff": item.setData(try LinkImportFixture.imageData(.tiff), forType: .tiff)
        case "jpeg": item.setData(try LinkImportFixture.imageData(.jpeg), forType: NSPasteboard.PasteboardType("public.jpeg"))
        default: item.setData(try LinkImportFixture.imageData(.png), forType: .png)
        }
        fixture.write(item)

        await fixture.paste()

        #expect(fixture.model.board.items.count == 1)
        let image = try #require(fixture.model.board.items.first)
        #expect(image.kind == .image)
        #expect(image.title == "Imagem colada")
        #expect(fixture.storedFileIsPNG(image))
        #expect(image.imageMetadata?.pixelWidth == 40)
        #expect(fixture.model.lastError == nil)
    }

    @Test("PDF copiado junto com o endereço continua virando PDF")
    func pdfWithAddressStaysPDF() async throws {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        let item = Self.addressItem("https://example.com/relatorio.pdf", name: "Relatório")
        item.setData(Data("%PDF-1.4".utf8), forType: .pdf)
        fixture.write(item)

        await fixture.paste()

        #expect(fixture.model.board.items.map(\.kind) == [.pdf])
    }

    @Test("O endereço de um arquivo de imagem é um link: o app não baixa nem lê a imagem")
    func addressOfAnImageFileIsALink() async {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        fixture.write(Self.addressItem("https://example.com/fotos/praia.png"))

        await fixture.paste()

        #expect(fixture.model.board.items.map(\.kind) == [.link])
    }

    @Test("Sem nada que vire cartão, o ⌘V avisa em lastError")
    func emptyPasteboardReportsAnError() async {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }

        await fixture.paste()

        #expect(fixture.model.board.items.isEmpty)
        #expect(fixture.model.lastError == "O conteúdo copiado não pôde virar um cartão.")
    }

    // MARK: Imagem em tipo antigo

    @Test("Imagem que um app só declara no tipo antigo (NeXT TIFF v4.0) vira cartão de imagem")
    func imageInLegacyTypeBecomesImage() async throws {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        let legacyTIFF = NSPasteboard.PasteboardType("NeXT TIFF v4.0 pasteboard type")
        #expect(fixture.pasteboard.setData(try LinkImportFixture.imageData(.tiff), forType: legacyTIFF))

        await fixture.paste()

        #expect(fixture.model.board.items.count == 1)
        let image = try #require(fixture.model.board.items.first)
        #expect(image.kind == .image)
        #expect(image.title == "Imagem colada")
        #expect(fixture.storedFileIsPNG(image))
        #expect(image.imageMetadata?.pixelWidth == 40)
        #expect(fixture.model.lastError == nil)
    }

    @Test("Copiar Link (endereço e texto) continua virando link, e a leitura de imagem em tipo antigo não o toma")
    func copyLinkStaysALinkWithTheLegacyImageReading() async throws {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        fixture.write(Self.addressItem("https://example.com/artigo", name: "Artigo"))

        await fixture.paste()

        #expect(fixture.model.board.items.map(\.kind) == [.link])
        #expect(fixture.links.first?.title == "Artigo")
        #expect(fixture.model.lastError == nil)
    }

    @Test("Só texto continua sendo texto: a leitura de imagem em tipo antigo não encontra nada e passa a vez")
    func plainTextStaysTextWithTheLegacyImageReading() async throws {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        fixture.pasteboard.setString("lembrar de comprar café", forType: .string)

        await fixture.paste()

        let sticky = try #require(fixture.model.board.items.first)
        #expect(fixture.model.board.items.count == 1)
        #expect(sticky.kind == .sticky)
        #expect(sticky.text == "lembrar de comprar café")
    }

    // MARK: Favorito do Safari

    @Test("Item com a lista de favoritos do Safari vira link com resumo e imagem")
    func bookmarkListBecomesRichLink() async throws {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        let item = NSPasteboardItem()
        item.setData(
            try Self.bookmarkListData(
                "https://www.apple.com/br/mac/", title: "Mac – Apple (BR)", summary: "O Mac mais rápido de todos.",
                image: "https://www.apple.com/br/mac/capa.jpg"),
            forType: Self.bookmarkList)
        fixture.write(item)

        await fixture.paste()

        #expect(fixture.model.board.items.count == 1)
        let link = try #require(fixture.links.first)
        #expect(link.title == "Mac – Apple (BR)")
        #expect(link.link?.url.absoluteString == "https://www.apple.com/br/mac/")
        #expect(link.link?.summary == "O Mac mais rápido de todos.")
        #expect(link.link?.remoteImageURL?.absoluteString == "https://www.apple.com/br/mac/capa.jpg")
    }

    @Test("Um favorito com todos os tipos do Safari juntos vira um só cartão, com o que há de mais rico")
    func fullSafariFavoriteBecomesOneRichCard() async throws {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        let address = "https://www.apple.com/br/mac/"
        let item = Self.addressItem(address, name: "Mac")
        item.setData(
            try Self.bookmarkListData(
                address, title: "Mac – Apple (BR)", summary: "O Mac mais rápido.", image: "https://www.apple.com/capa.jpg"),
            forType: Self.bookmarkList)
        item.setData(try Self.metadataData(title: "Mac (metadados)", url: address), forType: Self.linkMetadata)
        fixture.write(item)
        fixture.addLegacy([[address], ["Mac"]], forType: Self.urlsWithTitles)

        await fixture.paste()

        #expect(fixture.model.board.items.count == 1)
        let link = try #require(fixture.links.first)
        #expect(link.title == "Mac – Apple (BR)")
        #expect(link.link?.summary == "O Mac mais rápido.")
        #expect(link.link?.remoteImageURL?.absoluteString == "https://www.apple.com/capa.jpg")
    }

    @Test("Pasta de favoritos copiada vira um link por favorito, na ordem")
    func bookmarkFolderBecomesLinks() async throws {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        let folder: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeList",
            "Children": [
                ["URLString": "https://example.com/a", "URIDictionary": ["title": "A"]] as [String: Any],
                ["URLString": "https://example.com/b", "URIDictionary": ["title": "B"]] as [String: Any],
            ],
        ]
        let item = NSPasteboardItem()
        item.setData(
            try PropertyListSerialization.data(fromPropertyList: [folder], format: .binary, options: 0), forType: Self.bookmarkList)
        fixture.write(item)

        await fixture.paste()

        #expect(fixture.links.map(\.title) == ["A", "B"])
    }

    @Test("Lista de favoritos ilegível não impede o link do endereço")
    func garbageBookmarkListStillGivesTheAddress() async {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        let item = Self.addressItem("https://example.com/a", name: "Título")
        item.setData(Data("não é uma lista de propriedades".utf8), forType: Self.bookmarkList)
        fixture.write(item)
        fixture.addLegacy("também não é [[endereços], [títulos]]", forType: Self.urlsWithTitles)

        await fixture.paste()

        #expect(fixture.links.map(\.title) == ["Título"])
    }

    // MARK: Apoio

    /// Um item como o de “Copiar Link”: o endereço, o nome da página (se houver) e o endereço como texto.
    private static func addressItem(_ address: String, name: String? = nil) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(address, forType: .URL)
        if let name { item.setString(name, forType: urlName) }
        item.setString(address, forType: .string)
        return item
    }

    private static func bookmarkListData(_ address: String, title: String, summary: String, image: String) throws -> Data {
        let entry: [String: Any] = [
            "URLString": address, "URIDictionary": ["title": title], "previewText": summary, "imageURL": image,
            "WebBookmarkType": "WebBookmarkTypeLeaf", "dateAdded": Date(timeIntervalSince1970: 1_700_000_000),
        ]
        return try PropertyListSerialization.data(fromPropertyList: [entry], format: .binary, options: 0)
    }

    private static func metadataData(title: String?, url: String) throws -> Data {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.url = URL(string: url)
        return try NSKeyedArchiver.archivedData(withRootObject: metadata, requiringSecureCoding: true)
    }
}
