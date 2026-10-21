import Foundation
import Testing

@testable import MuralKit

@Suite("Gravação de links")
struct LinkInfoCodingTests {
    /// 2026-10-20T12:00:00Z; segundos inteiros, porque o `BoardStore` grava datas em ISO-8601 sem frações.
    static let noon = Date(timeIntervalSince1970: 1_792_497_600)

    private func temporaryStore() -> BoardStore {
        BoardStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("MuralKitLinks-\(UUID().uuidString)"))
    }

    /// Grava um `board.json` escrito à mão, para testar a leitura pelo mesmo caminho do app.
    private func storeWithBoard(json: String) throws -> BoardStore {
        let store = temporaryStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: store.fileURL)
        return store
    }

    /// Mesma estratégia de datas do `BoardStore`.
    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// Mural gravado antes de existir o campo `link`.
    private static let legacyBoardJSON = """
        {
          "formatVersion" : 1,
          "items" : [
            {
              "createdAt" : "2026-10-01T12:00:00Z",
              "id" : "5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01",
              "kind" : "folder",
              "position" : { "x" : 420, "y" : 80 },
              "tag" : "CLIENT 001",
              "title" : "The Cottage"
            },
            {
              "createdAt" : "2026-10-01T12:00:01Z",
              "id" : "7C1D5E3F-9D1C-4C2A-8E86-4F2B8A3BAD02",
              "kind" : "sticky",
              "parentID" : "5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01",
              "position" : { "x" : 0, "y" : 0 },
              "stickyColor" : "yellow",
              "text" : "Ideia",
              "title" : "Ideia"
            },
            {
              "createdAt" : "2026-10-01T12:00:02Z",
              "fileName" : "9E3F7A5B-AF3E-4E4C-A0A8-6B4DAA5CDF03.png",
              "id" : "9E3F7A5B-AF3E-4E4C-A0A8-6B4DAA5CDF03",
              "kind" : "image",
              "position" : { "x" : 80, "y" : 80 },
              "title" : "Foto"
            }
          ]
        }
        """

    /// Mural gravado por um formato anterior dos links, que ainda guardava `importedFrom`, `origin` e `folderPath`.
    private static let previousLinkFormatBoardJSON = """
        {
          "formatVersion" : 1,
          "items" : [
            {
              "createdAt" : "2026-10-19T12:00:00Z",
              "id" : "A1D4C7E2-5B3F-4E8A-9C61-2D7B0F3E8A11",
              "importedFrom" : "safariFavorites",
              "kind" : "folder",
              "position" : { "x" : 80, "y" : 80 },
              "title" : "Favoritos do Safari"
            },
            {
              "createdAt" : "2026-10-19T12:00:01Z",
              "id" : "B2E5D8F3-6C40-4F9B-8D72-3E8C1A4F9B22",
              "kind" : "link",
              "link" : {
                "folderPath" : [ "Barra de Favoritos", "Design" ],
                "origin" : "safariFavorites",
                "pageTitle" : "Apple",
                "preview" : { "ready" : { "fetchedAt" : "2026-10-20T12:00:00Z" } },
                "url" : "https://apple.com/mac"
              },
              "parentID" : "A1D4C7E2-5B3F-4E8A-9C61-2D7B0F3E8A11",
              "position" : { "x" : 0, "y" : 0 },
              "title" : "Apple"
            },
            {
              "createdAt" : "2026-10-19T12:00:02Z",
              "id" : "C3F6E9A4-7D51-40AC-9E83-4F9D2B5AAC33",
              "kind" : "link",
              "link" : { "origin" : "pasted", "url" : "https://swift.org" },
              "position" : { "x" : 300, "y" : 80 },
              "title" : "swift.org"
            }
          ]
        }
        """

    @Test("Mural gravado antes dos links continua abrindo")
    func legacyBoardStillOpens() throws {
        let store = try storeWithBoard(json: Self.legacyBoardJSON)
        defer { try? FileManager.default.removeItem(at: store.directory) }

        let board = try #require(try store.load())
        #expect(board.items.map(\.kind) == [.folder, .sticky, .image])
        #expect(board.items.allSatisfy { $0.link == nil })
        #expect(board.items.first { $0.kind == .sticky }?.text == "Ideia")
    }

    @Test("Chaves antigas origin, folderPath e importedFrom são ignoradas ao abrir e somem na próxima gravação")
    func previousLinkFormatStillOpens() throws {
        let store = try storeWithBoard(json: Self.previousLinkFormatBoardJSON)
        defer { try? FileManager.default.removeItem(at: store.directory) }

        let board = try #require(try store.load())
        #expect(board.items.map(\.kind) == [.folder, .link, .link])
        let apple = try #require(board.items[1].link)
        #expect(apple.url.absoluteString == "https://apple.com/mac")
        #expect(apple.pageTitle == "Apple")
        #expect(apple.preview == .ready(fetchedAt: Self.noon))
        #expect(apple.remoteImageURL == nil)
        #expect(board.items[2].link == LinkInfo(url: try #require(URL(string: "https://swift.org"))))

        try store.save(board)
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(!text.contains("origin") && !text.contains("folderPath") && !text.contains("importedFrom"))
        #expect(try store.load() == board)
    }

    @Test("Mural sem links é gravado sem a chave nova")
    func boardWithoutLinksKeepsTheOldFormat() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.save(Board(items: [BoardItem(kind: .folder, title: "Pasta"), BoardItem(kind: .sticky, title: "Nota", text: "x")]))

        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(!text.contains("\"link\""))
    }

    @Test("Mural com links em cada estado de prévia, com e sem imagem remota, volta igual do disco")
    func roundTripThroughBoardStore() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let folder = BoardItem(kind: .folder, title: "Referências", createdAt: Self.noon, position: BoardPoint(x: 80, y: 80))
        let wikipedia = try #require(URL(string: "https://pt.wikipedia.org/wiki/São_Paulo?x=1&y=2#historia"))
        let wikipediaCover = try #require(URL(string: "https://upload.wikimedia.org/capa.jpg"))
        let offline = try #require(URL(string: "http://fora-do-ar.example/"))
        let offlineCover = try #require(URL(string: "http://fora-do-ar.example/capa.png"))
        let pending = BoardItem(
            kind: .link, title: "apple.com", createdAt: Self.noon, position: BoardPoint(x: 300, y: 80),
            link: LinkInfo(url: try #require(URL(string: "https://apple.com"))))
        let ready = BoardItem(
            kind: .link, title: "São Paulo", createdAt: Self.noon, parentID: folder.id,
            link: LinkInfo(
                url: wikipedia, pageTitle: "São Paulo – Wikipédia", siteName: "Wikipédia", summary: "Município brasileiro.",
                remoteImageURL: wikipediaCover, previewImageFile: "A1B2.jpg", iconFile: "C3D4.png",
                preview: .ready(fetchedAt: Self.noon)))
        let failed = BoardItem(
            kind: .link, title: "fora do ar", createdAt: Self.noon, parentID: folder.id,
            link: LinkInfo(
                url: offline, summary: "Veio junto com o arrasto", remoteImageURL: offlineCover,
                preview: .failed(at: Self.noon, attempts: 3)))
        let board = Board(items: [folder, pending, ready, failed])

        try store.save(board)
        let loaded = try #require(try store.load())

        #expect(loaded == board)
        #expect(loaded.item(id: pending.id)?.link?.preview == .pending)
        #expect(loaded.item(id: ready.id)?.link?.preview == .ready(fetchedAt: Self.noon))
        #expect(loaded.item(id: failed.id)?.link?.preview == .failed(at: Self.noon, attempts: 3))
        #expect(loaded.item(id: failed.id)?.link?.remoteImageURL?.absoluteString == "http://fora-do-ar.example/capa.png")
        #expect(loaded.item(id: pending.id)?.link?.remoteImageURL == nil)
    }

    @Test("Link só com endereço abre com os padrões e ignora chaves desconhecidas")
    func missingFieldsUseDefaults() throws {
        let json = #"{"url":"https://apple.com/mac","campoDeUmaVersaoFutura":{"a":1}}"#
        let info = try Self.decoder().decode(LinkInfo.self, from: Data(json.utf8))

        #expect(info == LinkInfo(url: try #require(URL(string: "https://apple.com/mac"))))
        #expect(info.preview == .pending)
        #expect(info.pageTitle == nil && info.siteName == nil && info.summary == nil)
        #expect(info.remoteImageURL == nil && info.previewImageFile == nil && info.iconFile == nil)
    }

    @Test("Link lê o endereço da imagem remota quando ele existe")
    func remoteImageURLIsRead() throws {
        let json = #"{"url":"https://apple.com/mac","remoteImageURL":"https://cdn.example.com/capa.jpg","previewImageFile":"A1.jpg"}"#
        let info = try Self.decoder().decode(LinkInfo.self, from: Data(json.utf8))

        #expect(info.remoteImageURL?.absoluteString == "https://cdn.example.com/capa.jpg")
        #expect(info.previewImageFile == "A1.jpg")
    }

    @Test("Sem endereço o link não abre")
    func urlIsRequired() {
        for json in ["{}", #"{"pageTitle":"Apple","preview":{"pending":{}}}"#, #"{"origin":"pasted"}"#] {
            #expect(throws: DecodingError.self) { try Self.decoder().decode(LinkInfo.self, from: Data(json.utf8)) }
        }
    }

    @Test(
        "Cada estado da prévia usa o formato gravado em disco",
        arguments: [
            (#"{"pending":{}}"#, LinkPreviewState.pending),
            (#"{"ready":{"fetchedAt":"2026-10-20T12:00:00Z"}}"#, .ready(fetchedAt: LinkInfoCodingTests.noon)),
            (#"{"failed":{"at":"2026-10-20T12:00:00Z","attempts":2}}"#, .failed(at: LinkInfoCodingTests.noon, attempts: 2)),
        ])
    func previewStateFormat(json: String, state: LinkPreviewState) throws {
        #expect(try Self.decoder().decode(LinkPreviewState.self, from: Data(json.utf8)) == state)
        #expect(String(decoding: try Self.encoder().encode(state), as: UTF8.self) == json)
    }

    @Test("O tipo link é gravado como \"link\" e não guarda arquivo")
    func linkKind() throws {
        #expect(ItemKind.link.rawValue == "link")
        #expect(!ItemKind.link.storesFile)
        #expect(try Self.decoder().decode(ItemKind.self, from: Data(#""link""#.utf8)) == .link)
    }
}
