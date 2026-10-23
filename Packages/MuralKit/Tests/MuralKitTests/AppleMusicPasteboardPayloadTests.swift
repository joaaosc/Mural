import Foundation
import Testing

@testable import MuralKit

/// Usa amostras sintéticas com as chaves observadas no Música 1.7.2 (macOS 27.2); nenhum dado real é versionado.
@Suite("Dados do Música na área de transferência")
struct AppleMusicPasteboardPayloadTests {
    // MARK: Apoio

    private func json(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private func albumObject() -> [String: Any] {
        [
            "attributes": [
                "artistName": "Banda Inventada & Convidada",
                "isPrerelease": false,
                "artwork": [
                    "height": 4000, "width": 4000,
                    "textColor1": "020201", "textColor2": "232321", "textColor3": "32302d", "textColor4": "4c4a47",
                    "bgColor": "F1E9DD",
                    "url": "https://exemplo.test/image/thumb/capa.jpg/{w}x{h}bb.{f}",
                ],
                "genreNames": ["Brazilian", "Music"],
                "isCompilation": false,
                "recordLabel": "Gravadora Fictícia",
                "url": "https://music.apple.com/br/album/disco-inventado-single/1000000001?l=en-GB",
                "audioTraits": ["lossless", "lossy-stereo"],
                "upc": "0000000000001",
                "releaseDate": "2026-01-15",
                "trackCount": 1,
                "playParams": ["catalogId": "1000000001", "id": "1000000001", "kind": "album"],
                "name": "Disco Inventado - Single",
                "isSingle": true,
            ] as [String: Any],
            "meta": [
                "musicKit_identifierSet": [
                    "dataSources": ["catalog", "localLibrary"],
                    "type": "Album",
                    "catalogID": ["kind": "adamID", "value": "1000000001"],
                    "id": "1000000001",
                    "isLibrary": false,
                ] as [String: Any]
            ],
            "id": "1000000001",
            "href": "/v1/catalog/br/albums/1000000001",
            "type": "albums",
        ]
    }

    private func roundTrip(_ value: Any) throws -> Any {
        let data = try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
        return try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    }

    private func trackEntry(
        id: Int, name: String? = "Faixa Um", disc: Int? = nil, number: Int? = nil, store: String? = nil
    ) -> [String: Any] {
        var entry: [String: Any] = [
            "Album": "Álbum Inventado", "Apple Music": true, "Artist": "Artista Inventado",
            "Composer": "Compositor Fictício", "Genre": "MPB",
            "Release Date": Date(timeIntervalSince1970: 568_036_800),  // 1988-01-01T12:00:00Z
            "Total Time": 246_293, "Track Count": 12, "Track ID": id, "Track Type": "Remote", "Year": 1988,
            "Persistent ID": "0123456789ABCDEF",
        ]
        if let name { entry["Name"] = name }
        if let disc { entry["Disc Number"] = disc }
        if let number { entry["Track Number"] = number }
        if let store { entry["Store URL"] = store }
        return entry
    }

    private func library(tracks: [[String: Any]], playlist: [Int]? = nil) -> [String: Any] {
        var dict: [String: Any] = [:]
        for track in tracks { dict[String(track["Track ID"] as! Int)] = track }
        var root: [String: Any] = ["Major Version": 1, "Minor Version": 1, "Tracks": dict]
        if let playlist {
            root["Playlists"] = [
                [
                    "Description": "", "Name": "Lista", "Playlist ID": 1,
                    "Playlist Items": playlist.map { ["Track ID": $0] },
                ] as [String: Any]
            ]
        }
        return root
    }

    // MARK: JSON do item genérico

    @Test("Álbum completo mapeia todos os campos")
    func fullAlbum() throws {
        let result = AppleMusicPasteboardPayload.snapshots(fromGenericItemJSON: try json(albumObject()))

        #expect(
            result == [
                MusicSnapshot(
                    kind: .album, catalogID: "1000000001", storefront: "br",
                    url: URL(string: "https://music.apple.com/br/album/disco-inventado-single/1000000001"),
                    title: "Disco Inventado - Single", subtitle: "Banda Inventada & Convidada",
                    artworkTemplate: "https://exemplo.test/image/thumb/capa.jpg/{w}x{h}bb.{f}",
                    backgroundHex: "#f1e9dd", primaryTextHex: "#020201", secondaryTextHex: "#232321",
                    trackCount: 1, releaseDate: "2026-01-15")
            ])
    }

    @Test("Faixa com duração em milissegundos e nome do álbum")
    func song() throws {
        let object: [String: Any] = [
            "attributes": [
                "name": "Faixa Inventada", "artistName": "Artista X", "albumName": "Álbum Y",
                "durationInMillis": 215_500,
                "playParams": ["catalogId": 2_000_000_002, "id": "2000000002", "kind": "song"] as [String: Any],
                "url": "https://music.apple.com/br/album/album-y/2000000001?i=2000000002",
            ] as [String: Any],
            "id": "2000000002", "href": "/v1/catalog/br/songs/2000000002", "type": "songs",
        ]
        let snapshot = try #require(AppleMusicPasteboardPayload.snapshots(fromGenericItemJSON: try json(object)).first)
        #expect(snapshot.kind == .song)
        #expect(snapshot.catalogID == "2000000002")
        #expect(snapshot.albumTitle == "Álbum Y")
        #expect(snapshot.duration == 215.5)
        #expect(snapshot.url?.absoluteString == "https://music.apple.com/br/album/album-y/2000000001?i=2000000002")
    }

    @Test("Playlist do catálogo usa o curador como subtítulo")
    func catalogPlaylist() throws {
        let object: [String: Any] = [
            "attributes": [
                "name": "Lista Editorial", "curatorName": "Curadoria Fictícia",
                "playParams": ["id": "pl.abc", "kind": "playlist"] as [String: Any],
                "url": "https://music.apple.com/us/playlist/lista-editorial/pl.abc",
            ] as [String: Any],
            "id": "pl.abc", "href": "/v1/catalog/us/playlists/pl.abc", "type": "playlists",
        ]
        let snapshot = try #require(AppleMusicPasteboardPayload.snapshots(fromGenericItemJSON: try json(object)).first)
        #expect(snapshot.kind == .playlist)
        #expect(snapshot.catalogID == "pl.abc")
        #expect(snapshot.storefront == "us")
        #expect(snapshot.subtitle == "Curadoria Fictícia")
        #expect(snapshot.libraryPlaylistName == nil)
    }

    @Test("library-playlists sem catalogId vira playlist própria pelo nome; o id local não vira catálogo")
    func libraryPlaylist() throws {
        let object: [String: Any] = [
            "attributes": ["name": "  Minha Lista ", "playParams": ["id": "p.XyZ", "isLibrary": true] as [String: Any]]
                as [String: Any],
            "id": "p.XyZ", "type": "library-playlists",
        ]
        let snapshot = try #require(AppleMusicPasteboardPayload.snapshots(fromGenericItemJSON: try json(object)).first)
        #expect(snapshot.kind == .playlist)
        #expect(snapshot.catalogID == nil)
        #expect(snapshot.libraryPlaylistName == "Minha Lista")
        #expect(snapshot.title == "Minha Lista")
    }

    @Test("library-songs com catalogId usa o catálogo")
    func librarySongWithCatalogID() throws {
        let object: [String: Any] = [
            "attributes": ["name": "Faixa", "playParams": ["catalogId": "55"] as [String: Any]] as [String: Any],
            "id": "i.local", "type": "library-songs",
        ]
        let snapshot = try #require(AppleMusicPasteboardPayload.snapshots(fromGenericItemJSON: try json(object)).first)
        #expect(snapshot.kind == .song)
        #expect(snapshot.catalogID == "55")
    }

    @Test("Sem catalogId, o id de topo vale só fora da biblioteca")
    func topLevelID() throws {
        let catalog: [String: Any] = ["attributes": ["name": "A"], "id": "77", "type": "albums"]
        #expect(AppleMusicPasteboardPayload.snapshots(fromGenericItemJSON: try json(catalog)).first?.catalogID == "77")
        let local: [String: Any] = ["attributes": ["name": "A"], "id": "77", "type": "library-albums"]
        #expect(AppleMusicPasteboardPayload.snapshots(fromGenericItemJSON: try json(local)).first?.catalogID == nil)
    }

    @Test("Sem catalogId, a url aceita completa kind, id e loja")
    func urlFillsCatalogID() throws {
        let object: [String: Any] = [
            "attributes": ["name": "A", "url": "https://music.apple.com/br/album/a/88?l=pt"] as [String: Any],
            "type": "library-albums",
        ]
        let snapshot = try #require(AppleMusicPasteboardPayload.snapshots(fromGenericItemJSON: try json(object)).first)
        #expect(snapshot.catalogID == "88")
        #expect(snapshot.storefront == "br")
        #expect(snapshot.url?.absoluteString == "https://music.apple.com/br/album/a/88")
    }

    @Test("Url que o leitor não aceita fica sem url")
    func unsupportedURL() throws {
        let object: [String: Any] = [
            "attributes": ["name": "A", "url": "https://music.apple.com/br/artist/x/1"] as [String: Any],
            "id": "5", "type": "albums",
        ]
        let snapshot = try #require(AppleMusicPasteboardPayload.snapshots(fromGenericItemJSON: try json(object)).first)
        #expect(snapshot.url == nil)
        #expect(snapshot.catalogID == "5")
    }

    @Test("Tipo desconhecido e nome vazio são ignorados")
    func ignoredObjects() throws {
        let unknown: [String: Any] = ["attributes": ["name": "A"], "type": "music-videos"]
        let empty: [String: Any] = ["attributes": ["name": "   "], "type": "albums"]
        let noName: [String: Any] = ["attributes": ["name": 12], "type": "albums"]
        let noAttributes: [String: Any] = ["type": "albums"]
        for object in [unknown, empty, noName, noAttributes] {
            #expect(AppleMusicPasteboardPayload.snapshots(fromGenericItemJSON: try json(object)).isEmpty)
        }
    }

    @Test("Lista de objetos mantém a ordem e pula o que não serve")
    func objectList() throws {
        var second = albumObject()
        second["attributes"] = ["name": "Segundo"]
        second["id"] = "2"
        let list: [Any] = [albumObject(), ["type": "artists"], 42, second]
        let result = AppleMusicPasteboardPayload.snapshots(fromGenericItemJSON: try json(list))
        #expect(result.map(\.title) == ["Disco Inventado - Single", "Segundo"])
    }

    @Test("JSON inválido ou de outro tipo devolve vazio")
    func invalidJSON() throws {
        #expect(AppleMusicPasteboardPayload.snapshots(fromGenericItemJSON: Data("não é json".utf8)).isEmpty)
        #expect(AppleMusicPasteboardPayload.snapshots(fromGenericItemJSON: Data()).isEmpty)
        #expect(AppleMusicPasteboardPayload.snapshots(fromGenericItemJSON: Data("\"texto\"".utf8)).isEmpty)
    }

    @Test("Máscara de campos com tipo errado é ignorada sem travar")
    func wrongTypes() throws {
        let object: [String: Any] = [
            "attributes": [
                "name": "A", "artistName": 5, "trackCount": "três", "releaseDate": 2026,
                "durationInMillis": "rápido", "artwork": "nenhuma", "playParams": [1, 2],
            ] as [String: Any],
            "type": "albums",
        ]
        let snapshot = try #require(AppleMusicPasteboardPayload.snapshots(fromGenericItemJSON: try json(object)).first)
        #expect(snapshot == MusicSnapshot(kind: .album, title: "A"))
    }

    @Test("Limite de 200 itens por leitura no JSON")
    func jsonLimit() throws {
        let list = (0..<250).map { ["attributes": ["name": "Item \($0)"], "type": "albums"] as [String: Any] }
        #expect(AppleMusicPasteboardPayload.snapshots(fromGenericItemJSON: try json(list)).count == 200)
    }

    // MARK: Metadados de faixa

    @Test("Faixa do plist mapeia todos os campos e não copia ids locais")
    func fullTrack() throws {
        let root = library(
            tracks: [trackEntry(id: 101, store: "itmss://itunes.com/album?p=1000000001&i=1000000002")],
            playlist: [101])
        let result = AppleMusicPasteboardPayload.snapshots(fromTrackMetadata: try roundTrip(root))

        #expect(
            result == [
                MusicSnapshot(
                    kind: .song, catalogID: "1000000002",
                    url: URL(string: "https://music.apple.com/album/1000000001?i=1000000002"),
                    title: "Faixa Um", subtitle: "Artista Inventado", albumTitle: "Álbum Inventado",
                    releaseDate: "1988-01-01", duration: 246.293)
            ])
        #expect(result[0].libraryID == nil)
    }

    @Test("A data de lançamento sai em UTC")
    func releaseDateUTC() throws {
        var entry = trackEntry(id: 1)
        entry["Release Date"] = Date(timeIntervalSince1970: 567_993_599)  // 1987-12-31T23:59:59Z
        let result = AppleMusicPasteboardPayload.snapshots(fromTrackMetadata: try roundTrip(library(tracks: [entry])))
        #expect(result.first?.releaseDate == "1987-12-31")
    }

    @Test("Ordem: itens da playlist primeiro, depois disco, faixa e id")
    func trackOrdering() throws {
        let tracks = [
            trackEntry(id: 1, name: "D2F2", disc: 2, number: 2),
            trackEntry(id: 2, name: "D1F2", disc: 1, number: 2),
            trackEntry(id: 3, name: "Da lista B", disc: 1, number: 1),
            trackEntry(id: 4, name: "D1F1", disc: 1, number: 1),
            trackEntry(id: 5, name: "Da lista A", disc: 3, number: 9),
            trackEntry(id: 6, name: "Sem numeração"),
        ]
        // 99 não existe; 5 repete; ambos devem ser ignorados na repetição.
        let root = library(tracks: tracks, playlist: [5, 99, 3, 5])
        let result = AppleMusicPasteboardPayload.snapshots(fromTrackMetadata: try roundTrip(root))
        #expect(result.map(\.title) == ["Da lista A", "Da lista B", "Sem numeração", "D1F1", "D1F2", "D2F2"])
    }

    @Test("Sem playlist, ordena pelo disco e pela faixa")
    func orderingWithoutPlaylist() throws {
        let tracks = [
            trackEntry(id: 10, name: "Segunda", disc: 1, number: 2),
            trackEntry(id: 11, name: "Primeira", disc: 1, number: 1),
        ]
        let result = AppleMusicPasteboardPayload.snapshots(fromTrackMetadata: try roundTrip(library(tracks: tracks)))
        #expect(result.map(\.title) == ["Primeira", "Segunda"])
    }

    @Test("Faixa sem Store URL válido vira música sem catálogo e sem url")
    func trackWithoutStoreURL() throws {
        let tracks = [
            trackEntry(id: 1, name: "Sem loja"),
            trackEntry(id: 2, name: "Loja ruim", store: "https://exemplo.test/album/1"),
        ]
        let result = AppleMusicPasteboardPayload.snapshots(fromTrackMetadata: try roundTrip(library(tracks: tracks)))
        #expect(result.count == 2)
        for snapshot in result {
            #expect(snapshot.kind == .song)
            #expect(snapshot.catalogID == nil)
            #expect(snapshot.url == nil)
        }
    }

    @Test("Faixa sem nome é ignorada")
    func trackWithoutName() throws {
        let tracks = [trackEntry(id: 1, name: nil), trackEntry(id: 2, name: "   "), trackEntry(id: 3, name: "Boa")]
        let result = AppleMusicPasteboardPayload.snapshots(fromTrackMetadata: try roundTrip(library(tracks: tracks)))
        #expect(result.map(\.title) == ["Boa"])
    }

    @Test("Tracks ausente, de tipo errado ou raiz errada devolve vazio")
    func invalidTrackMetadata() throws {
        #expect(AppleMusicPasteboardPayload.snapshots(fromTrackMetadata: try roundTrip(["Major Version": 1])).isEmpty)
        #expect(AppleMusicPasteboardPayload.snapshots(fromTrackMetadata: try roundTrip(["Tracks": [1, 2]])).isEmpty)
        #expect(AppleMusicPasteboardPayload.snapshots(fromTrackMetadata: try roundTrip(["Tracks": "x"])).isEmpty)
        #expect(AppleMusicPasteboardPayload.snapshots(fromTrackMetadata: try roundTrip(["a", "b"])).isEmpty)
        #expect(AppleMusicPasteboardPayload.snapshots(fromTrackMetadata: "texto").isEmpty)
        #expect(AppleMusicPasteboardPayload.snapshots(fromTrackMetadata: try roundTrip(["Tracks": ["1": "x"]])).isEmpty)
    }

    @Test("Playlists com tipo errado não impedem a leitura das faixas")
    func brokenPlaylists() throws {
        var root = library(tracks: [trackEntry(id: 1)])
        root["Playlists"] = "quebrado"
        #expect(AppleMusicPasteboardPayload.snapshots(fromTrackMetadata: try roundTrip(root)).count == 1)
    }

    @Test("Limite de 200 itens por leitura no plist")
    func plistLimit() throws {
        let tracks = (1...250).map { trackEntry(id: $0, name: "Faixa \($0)", disc: 1, number: $0) }
        let result = AppleMusicPasteboardPayload.snapshots(fromTrackMetadata: try roundTrip(library(tracks: tracks)))
        #expect(result.count == 200)
        #expect(result.first?.title == "Faixa 1")
    }

    // MARK: Nome de playlist

    @Test("Nome de playlist própria")
    func playlistName() {
        let snapshot = AppleMusicPasteboardPayload.snapshot(fromPlaylistName: "Minha Lista")
        #expect(snapshot == MusicSnapshot(kind: .playlist, libraryPlaylistName: "Minha Lista", title: "Minha Lista"))
        #expect(AppleMusicPasteboardPayload.snapshot(fromPlaylistName: "  Lista \n")?.title == "Lista")
        #expect(AppleMusicPasteboardPayload.snapshot(fromPlaylistName: "  \n") == nil)
        #expect(AppleMusicPasteboardPayload.snapshot(fromPlaylistName: "") == nil)
    }
}
