import Foundation
import Testing

@testable import MuralKit

/// Usa listas de propriedades sintéticas com as chaves observadas no Safari 27.2; nenhum dado real é versionado.
@Suite("Dados do Safari na área de transferência")
struct SafariPasteboardPayloadTests {
    // MARK: Apoio

    private func address(_ text: String) throws -> URL {
        try #require(URL(string: text))
    }

    /// Ida e volta por uma lista de propriedades binária, como a área de transferência a entrega:
    /// os valores voltam como tipos do Foundation (`NSArray`, `NSDictionary`, `NSDate`…).
    private func roundTrip(_ value: Any) throws -> Any {
        let data = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
        return try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    }

    /// Uma folha como o Safari a grava, com as chaves que a leitura não usa.
    private func leaf(
        _ url: String, title: String? = nil, preview: String? = nil, image: String? = nil, extra: [String: Any] = [:]
    ) -> [String: Any] {
        var entry: [String: Any] = [
            "URLString": url,
            "WebBookmarkType": "WebBookmarkTypeLeaf",
            "WebBookmarkUUID": "8E0F7C52-6B1D-4C0B-9C47-0D6A5A1E7F10",
            "dateAdded": Date(timeIntervalSince1970: 1_700_000_000),
            "ReadingListNonSync": ["neverFetchMetadata": false],
        ]
        if let title { entry["URIDictionary"] = ["title": title] }
        if let preview { entry["previewText"] = preview }
        if let image { entry["imageURL"] = image }
        return entry.merging(extra) { _, new in new }
    }

    private func folder(_ title: String, _ children: [Any]) -> [String: Any] {
        ["WebBookmarkType": "WebBookmarkTypeList", "Title": title, "Children": children]
    }

    private func addresses(_ drafts: [LinkDraft]) -> [String] {
        drafts.map(\.url.absoluteString)
    }

    // MARK: Favoritos

    @Test("Um favorito vira rascunho com título, resumo e imagem; as outras chaves não atrapalham")
    func bookmarkLeaf() throws {
        let plist = try roundTrip([
            leaf(
                "https://www.apple.com/br/", title: "Apple (Brasil)", preview: "Site oficial da Apple.",
                image: "https://www.apple.com/og/capa.jpg")
        ])

        let drafts = SafariPasteboardPayload.drafts(fromBookmarkList: plist)

        #expect(
            drafts == [
                LinkDraft(
                    url: try address("https://www.apple.com/br/"), title: "Apple (Brasil)", summary: "Site oficial da Apple.",
                    imageURL: try address("https://www.apple.com/og/capa.jpg"))
            ])
    }

    @Test("Só o endereço é obrigatório: título, resumo e imagem ausentes ficam vazios")
    func bookmarkWithOnlyTheAddress() throws {
        let drafts = SafariPasteboardPayload.drafts(fromBookmarkList: try roundTrip([leaf("http://example.com/")]))

        #expect(drafts == [LinkDraft(url: try address("http://example.com/"))])
    }

    @Test("Texto em branco vira ausência, e o que sobra perde os espaços das pontas")
    func blankTextIsAbsent() throws {
        let plist = try roundTrip([
            leaf("https://example.com/a", title: "  Título \n", preview: " Resumo\t"),
            leaf("https://example.com/b", title: "   ", preview: "\n"),
            leaf("https://example.com/c", title: ""),
        ])

        let drafts = SafariPasteboardPayload.drafts(fromBookmarkList: plist)

        #expect(drafts.map(\.title) == ["Título", nil, nil])
        #expect(drafts.map(\.summary) == ["Resumo", nil, nil])
    }

    @Test("A imagem só vale se for da web; o favorito continua valendo sem ela")
    func nonWebImageIsDropped() throws {
        let images = ["file:///Users/test-user/capa.png", "data:image/png;base64,iVBORw0KGgo=", "capa.png", "ftp://example.com/capa.png", ""]
        let plist = try roundTrip(images.map { leaf("https://example.com/pagina", title: "Página", image: $0) })

        let drafts = SafariPasteboardPayload.drafts(fromBookmarkList: plist)

        #expect(drafts.count == images.count)
        #expect(drafts.allSatisfy { $0.imageURL == nil && $0.title == "Página" })
    }

    // MARK: Lista de Leitura

    @Test("Na Lista de Leitura o resumo vem de ReadingList.PreviewText quando não há previewText")
    func readingListSummary() throws {
        let item = leaf(
            "https://example.com/artigo", title: "Artigo",
            extra: ["ReadingList": ["PreviewText": "  Resumo da lista.\n", "DateAdded": Date(timeIntervalSince1970: 1_700_000_000)]])

        let drafts = SafariPasteboardPayload.drafts(fromBookmarkList: try roundTrip([item]))

        #expect(drafts == [LinkDraft(url: try address("https://example.com/artigo"), title: "Artigo", summary: "Resumo da lista.")])
    }

    @Test("previewText vale mais que ReadingList.PreviewText, e um previewText em branco cede a vez")
    func previewTextPriority() throws {
        let plist = try roundTrip([
            leaf("https://example.com/a", preview: "Do favorito", extra: ["ReadingList": ["PreviewText": "Da lista"]]),
            leaf("https://example.com/b", preview: "  \n", extra: ["ReadingList": ["PreviewText": "Da lista"]]),
            leaf("https://example.com/c", extra: ["ReadingList": ["PreviewText": "   "]]),
        ])

        let drafts = SafariPasteboardPayload.drafts(fromBookmarkList: plist)

        #expect(drafts.map(\.summary) == ["Do favorito", "Da lista", nil])
    }

    // MARK: Pastas

    @Test("Pastas são percorridas por dentro, e a ordem do Safari se mantém")
    func nestedFolders() throws {
        let plist = try roundTrip([
            leaf("https://example.com/1"),
            folder(
                "Pasta",
                [
                    leaf("https://example.com/2"),
                    folder("Dentro", [leaf("https://example.com/3"), folder("Vazia", [])]),
                    leaf("https://example.com/4"),
                ]),
            leaf("https://example.com/5"),
        ])

        let drafts = SafariPasteboardPayload.drafts(fromBookmarkList: plist)

        #expect(addresses(drafts) == (1...5).map { "https://example.com/\($0)" })
    }

    @Test("Um dicionário solto, sem a lista em volta, também é lido")
    func singleDictionary() throws {
        let single = SafariPasteboardPayload.drafts(fromBookmarkList: try roundTrip(leaf("https://example.com/a", title: "A")))
        let inFolder = SafariPasteboardPayload.drafts(
            fromBookmarkList: try roundTrip(folder("Pasta", [leaf("https://example.com/b"), leaf("https://example.com/c")])))

        #expect(addresses(single) == ["https://example.com/a"])
        #expect(addresses(inFolder) == ["https://example.com/b", "https://example.com/c"])
    }

    @Test("Pastas e atalhos sem endereço não geram rascunho")
    func entriesWithoutAddress() throws {
        let plist = try roundTrip([
            folder("Barra de Favoritos", []),
            ["WebBookmarkType": "WebBookmarkTypeProxy", "Title": "History"],
            folder("Com folha", [leaf("https://example.com/unica")]),
        ])

        #expect(addresses(SafariPasteboardPayload.drafts(fromBookmarkList: plist)) == ["https://example.com/unica"])
    }

    // MARK: Formatos inesperados

    @Test("Formatos inesperados são ignorados e o que dá para ler continua valendo")
    func garbageIsIgnored() throws {
        let junk: [Any] = [
            42, "texto", Data([1, 2, 3]), [1, 2, 3], [[String: Any]](), true, Date(timeIntervalSince1970: 0),
            ["URLString": 42],
            ["URLString": ["https://example.com/em-lista"]],
            ["URLString": ["URL": "https://example.com/em-dicionario"]],
            ["URLString": "ftp://example.com/arquivo"], ["URLString": "javascript:alert(1)"], ["URLString": "file:///Users/test-user/a.txt"],
            ["URLString": "mailto:someone@example.com"], ["URLString": "https://"], ["URLString": ""], ["URLString": "   "],
            ["URLString": "apple.com"], ["URLString": "duas palavras https://example.com/x"],
            ["Children": "não é lista"], ["Children": 7], ["Children": [1, "a", [2]]], ["Children": [String: Any]()],
            ["URIDictionary": ["title": "Sem endereço"], "previewText": "Sem endereço"],
        ]
        let withWrongTypes = leaf(
            "https://example.com/tipos-errados",
            extra: ["URIDictionary": "Título solto", "previewText": ["x"], "imageURL": 7, "ReadingList": "texto"])
        let good = leaf("https://example.com/boa", title: "Boa")

        let drafts = SafariPasteboardPayload.drafts(fromBookmarkList: try roundTrip(junk + [withWrongTypes, good]))

        #expect(
            drafts == [
                LinkDraft(url: try address("https://example.com/tipos-errados")),
                LinkDraft(url: try address("https://example.com/boa"), title: "Boa"),
            ])
    }

    @Test("Algo que não é lista nem dicionário não gera nada")
    func nonCollectionsAreIgnored() {
        let values: [Any] = [
            42, 3.5, true, "https://example.com/solto", Data("https://example.com".utf8), Date(), URL(fileURLWithPath: "/tmp"), NSNull(),
            [Any](), [String: Any](), [[Any]](), [1, 2, 3],
        ]
        for value in values {
            #expect(SafariPasteboardPayload.drafts(fromBookmarkList: value).isEmpty, "\(value)")
        }
    }

    @Test("Um valor do Foundation com dicionários dentro também é lido")
    func foundationContainers() {
        let entry = NSMutableDictionary()
        entry["URLString"] = "https://example.com/foundation"
        entry["URIDictionary"] = NSDictionary(object: "Título", forKey: "title" as NSString)

        let drafts = SafariPasteboardPayload.drafts(fromBookmarkList: NSArray(object: entry))

        #expect(drafts.map(\.title) == ["Título"])
    }

    // MARK: Limites

    @Test("A leitura desce no máximo 16 pastas")
    func depthLimit() throws {
        // A pasta do nível n tem a folha n e a pasta n + 1; a folha n fica na profundidade n + 1.
        func chain(level: Int, last: Int) -> [String: Any] {
            var children: [Any] = [leaf("https://example.com/folha-\(level)")]
            if level < last { children.append(chain(level: level + 1, last: last)) }
            return folder("Nível \(level)", children)
        }

        let drafts = SafariPasteboardPayload.drafts(fromBookmarkList: try roundTrip([chain(level: 0, last: 24)]))

        #expect(addresses(drafts) == (0...15).map { "https://example.com/folha-\($0)" })
    }

    @Test("Uma folha dentro de 16 pastas ainda é lida; dentro de 17, não")
    func depthBoundary() throws {
        func nest(_ levels: Int, around entry: [String: Any]) -> [String: Any] {
            (0..<levels).reduce(entry) { inner, level in folder("Nível \(level)", [inner]) }
        }

        let atLimit = nest(16, around: leaf("https://example.com/no-limite"))
        let pastLimit = nest(17, around: leaf("https://example.com/depois-do-limite"))

        #expect(addresses(SafariPasteboardPayload.drafts(fromBookmarkList: try roundTrip([atLimit]))) == ["https://example.com/no-limite"])
        #expect(SafariPasteboardPayload.drafts(fromBookmarkList: try roundTrip([pastLimit])).isEmpty)
    }

    @Test("No máximo 1000 rascunhos, os primeiros na ordem do Safari, em lista plana ou em pastas")
    func draftLimit() throws {
        let entries = (1...1500).map { leaf("https://example.com/\($0)") }
        let flat: [Any] = entries
        let nested: [Any] = [
            folder("A", Array(entries[0..<700])), folder("B", [folder("Funda", Array(entries[700...]))]),
        ]

        for list in [flat, nested] {
            let drafts = SafariPasteboardPayload.drafts(fromBookmarkList: try roundTrip(list))
            #expect(drafts.count == 1000)
            #expect(addresses(drafts) == (1...1000).map { "https://example.com/\($0)" })
        }
    }

    @Test("Uma estrutura que contém a si mesma não trava")
    func cycleTerminates() {
        let entry = NSMutableDictionary()
        entry["URLString"] = "https://example.com/ciclo"
        entry["Children"] = NSArray(object: entry)
        defer { entry.removeAllObjects() }

        let drafts = SafariPasteboardPayload.drafts(fromBookmarkList: NSArray(object: entry))

        #expect(drafts.count == 17)
    }

    // MARK: Endereços com títulos

    @Test("WebURLsWithTitlesPboardType: cada título fica com o endereço da mesma posição")
    func urlsWithTitles() throws {
        let plist = try roundTrip([["https://apple.com/mac", "http://swift.org/"], ["Mac – Apple", " Swift \n"]])

        let drafts = SafariPasteboardPayload.drafts(fromURLsWithTitles: plist)

        #expect(
            drafts == [
                LinkDraft(url: try address("https://apple.com/mac"), title: "Mac – Apple"),
                LinkDraft(url: try address("http://swift.org/"), title: "Swift"),
            ])
    }

    @Test("Título vazio ou ausente fica sem título, e um endereço descartado não desloca os títulos")
    func missingTitlesAndSkippedAddresses() throws {
        let shortTitles = try roundTrip([["https://example.com/a", "https://example.com/b", "https://example.com/c"], ["Só o primeiro"]])
        let noTitles = try roundTrip([["https://example.com/a", "https://example.com/b"]])
        let emptyTitle = try roundTrip([["https://example.com/a", "https://example.com/b"], ["", "B"]])
        let skipped = try roundTrip([["ftp://example.com/x", "https://example.com/b", "texto"], ["X", "B", "T"]])

        #expect(SafariPasteboardPayload.drafts(fromURLsWithTitles: shortTitles).map(\.title) == ["Só o primeiro", nil, nil])
        #expect(SafariPasteboardPayload.drafts(fromURLsWithTitles: noTitles).map(\.title) == [nil, nil])
        #expect(SafariPasteboardPayload.drafts(fromURLsWithTitles: emptyTitle).map(\.title) == [nil, "B"])
        #expect(
            SafariPasteboardPayload.drafts(fromURLsWithTitles: skipped) == [
                LinkDraft(url: try address("https://example.com/b"), title: "B")
            ])
    }

    @Test("Valores de outros tipos nas colunas são ignorados")
    func urlsWithTitlesGarbage() throws {
        let plist = try roundTrip([[1, "https://example.com/a", ["x"], "https://example.com/b"], [2, "A", 3, ["B"]]])

        let drafts = SafariPasteboardPayload.drafts(fromURLsWithTitles: plist)

        #expect(
            drafts == [
                LinkDraft(url: try address("https://example.com/a"), title: "A"), LinkDraft(url: try address("https://example.com/b")),
            ])
    }

    @Test("Algo que não é [[endereços], [títulos]] não gera nada")
    func urlsWithTitlesWrongShape() throws {
        let values: [Any] = [
            42, "https://example.com/a", Data(), [Any](), [[Any]](), [1, 2], ["https://example.com/a", "Título"],
            ["https://example.com/a": "Título"], [["endereço": "https://example.com/a"]], [NSNull()],
        ]
        for value in values {
            #expect(SafariPasteboardPayload.drafts(fromURLsWithTitles: value).isEmpty, "\(value)")
        }
    }

    @Test("No máximo 1000 endereços com títulos")
    func urlsWithTitlesLimit() throws {
        let addresses = (1...1200).map { "https://example.com/\($0)" }

        let drafts = SafariPasteboardPayload.drafts(fromURLsWithTitles: try roundTrip([addresses, addresses.map { "Título \($0)" }]))

        #expect(drafts.count == 1000)
        #expect(drafts.last?.url.absoluteString == "https://example.com/1000")
        #expect(drafts.last?.title == "Título https://example.com/1000")
    }
}
