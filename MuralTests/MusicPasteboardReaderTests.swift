import AppKit
import MuralKit
import Testing

@testable import Mural

/// Cada teste usa uma área de transferência privada e dados sintéticos.
@MainActor
struct MusicPasteboardReaderTests {
    private static let urlName = NSPasteboard.PasteboardType("public.url-name")

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("MuralTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }

    private static let albumJSON = """
        {"id":"111","type":"albums","href":"/v1/catalog/br/albums/111",
         "attributes":{"name":"Álbum de teste","artistName":"Artista de teste",
         "url":"https://music.apple.com/br/album/album-de-teste/111?l=en-GB",
         "artwork":{"url":"https://exemplo.com/{w}x{h}bb.{f}","bgColor":"112233"}}}
        """

    private static func plist(tracks: [String]) throws -> Data {
        var dictionary: [String: Any] = [:]
        for (index, name) in tracks.enumerated() {
            dictionary["\(index + 1)"] = ["Name": name, "Artist": "Artista de teste", "Track Number": index + 1]
        }
        return try PropertyListSerialization.data(fromPropertyList: ["Tracks": dictionary], format: .xml, options: 0)
    }

    private static func previewArchive() throws -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.setClassName("AMPMediaItemPreviewMetadata", for: FakePreview.self)
        // Na chave da raiz, como nos arquivos do Música: `encodeRootObject` não grava nela num arquivo com chaves.
        archiver.encode(FakePreview(), forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    private func item(_ pairs: [(NSPasteboard.PasteboardType, Data)]) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        for (type, data) in pairs { item.setData(data, forType: type) }
        return item
    }

    @Test("Álbum em genericmusicitem vira um rascunho sem capa")
    func albumJSON() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([item([(MusicPasteboardReader.genericItemType, Data(Self.albumJSON.utf8))])])

        let drafts = MusicPasteboardReader.drafts(from: pasteboard)

        #expect(drafts.count == 1)
        #expect(drafts[0].snapshot.kind == .album)
        #expect(drafts[0].snapshot.title == "Álbum de teste")
        #expect(drafts[0].artworkData == nil)
        #expect(MusicPasteboardReader.containsMusic(pasteboard))
    }

    @Test("Faixa com prévia entrega a capa em imagem que a pasta de prévias aceita")
    func trackWithPreview() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([
            item([
                (MusicPasteboardReader.trackMetadataType, try Self.plist(tracks: ["Faixa de teste"])),
                (MusicPasteboardReader.mediaItemPreviewType, try Self.previewArchive()),
            ])
        ])

        let drafts = MusicPasteboardReader.drafts(from: pasteboard)

        #expect(drafts.map(\.snapshot.title) == ["Faixa de teste"])
        let artwork = try #require(drafts[0].artworkData)
        #expect(LinkPreviewFiles.canStoreImage(artwork))
    }

    @Test("Plist com duas faixas não leva capa")
    func twoTracksHaveNoArtwork() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([
            item([
                (MusicPasteboardReader.trackMetadataType, try Self.plist(tracks: ["Faixa A", "Faixa B"])),
                (MusicPasteboardReader.mediaItemPreviewType, try Self.previewArchive()),
            ])
        ])

        let drafts = MusicPasteboardReader.drafts(from: pasteboard)

        #expect(drafts.count == 2)
        #expect(drafts.allSatisfy { $0.artworkData == nil })
    }

    @Test("Nome de playlist vira playlist própria")
    func playlistName() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([item([(MusicPasteboardReader.playlistNameType, Data("Lista de teste".utf8))])])

        let drafts = MusicPasteboardReader.drafts(from: pasteboard)

        #expect(drafts.map(\.snapshot.libraryPlaylistName) == ["Lista de teste"])
        #expect(drafts.map(\.snapshot.kind) == [.playlist])
    }

    @Test("Dois itens repetidos viram um")
    func duplicatesAreMerged() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let data = Data(Self.albumJSON.utf8)
        pasteboard.writeObjects([
            item([(MusicPasteboardReader.genericItemType, data)]), item([(MusicPasteboardReader.genericItemType, data)]),
        ])

        #expect(MusicPasteboardReader.drafts(from: pasteboard).count == 1)
    }

    @Test("Link music.apple.com com public.url-name vira música com o título")
    func appleMusicLink() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let link = NSPasteboardItem()
        link.setString("https://music.apple.com/br/album/album-de-teste/111?l=en-GB", forType: .URL)
        link.setString("Título do link", forType: Self.urlName)
        pasteboard.writeObjects([link])

        let drafts = MusicPasteboardReader.drafts(from: pasteboard)

        #expect(drafts.map(\.snapshot.title) == ["Título do link"])
        #expect(drafts.map(\.snapshot.kind) == [.album])
        #expect(MusicPasteboardReader.containsMusic(pasteboard))
    }

    @Test("Links misturados (um do Apple Music e um comum) não viram música")
    func mixedLinks() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let music = NSPasteboardItem()
        music.setString("https://music.apple.com/br/album/album-de-teste/111", forType: .URL)
        let other = NSPasteboardItem()
        other.setString("https://exemplo.com/pagina", forType: .URL)
        pasteboard.writeObjects([music, other])

        #expect(MusicPasteboardReader.drafts(from: pasteboard).isEmpty)
        #expect(!MusicPasteboardReader.containsMusic(pasteboard))
    }

    @Test("Sem nada do Música devolve vazio")
    func nothingFromMusic() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        #expect(MusicPasteboardReader.drafts(from: pasteboard).isEmpty)
        #expect(!MusicPasteboardReader.containsMusic(pasteboard))

        pasteboard.setString("texto qualquer", forType: .string)
        #expect(MusicPasteboardReader.drafts(from: pasteboard).isEmpty)
        #expect(!MusicPasteboardReader.containsMusic(pasteboard))
    }

    @Test("containsMusic só olha os tipos: dados inválidos do Música ainda contam")
    func containsMusicLooksAtTypesOnly() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([item([(MusicPasteboardReader.genericItemType, Data("lixo".utf8))])])

        #expect(MusicPasteboardReader.containsMusic(pasteboard))
        #expect(MusicPasteboardReader.drafts(from: pasteboard).isEmpty)
    }

    @Test("Arquivo de prévia com lixo ou grande demais devolve nil")
    func garbageArchive() {
        #expect(MusicPasteboardReader.artworkData(fromPreviewArchive: Data("lixo".utf8)) == nil)
        #expect(MusicPasteboardReader.artworkData(fromPreviewArchive: Data(count: 33 * 1024 * 1024)) == nil)
    }
}

/// Faz o papel do `AMPMediaItemPreviewMetadata` ao montar o arquivo de prévia dos testes.
@objc(MuralTestsFakeMusicPreview)
private nonisolated final class FakePreview: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    override init() { super.init() }
    required init?(coder: NSCoder) { nil }

    func encode(with coder: NSCoder) {
        coder.encode("Faixa de teste", forKey: "title")
        coder.encode("Artista de teste", forKey: "subtitle")
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return }
        if let data = bitmap.bitmapData { data.update(repeating: 180, count: bitmap.bytesPerRow * 64) }
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.addRepresentation(bitmap)
        coder.encode(image, forKey: "artwork")
    }
}
