import Foundation
import Testing

@testable import MuralKit

@Suite("Cartão de música: modelo")
struct MusicSnapshotTests {
    private func decode(_ json: String) throws -> MusicSnapshot {
        try JSONDecoder().decode(MusicSnapshot.self, from: Data(json.utf8))
    }

    @Test("Só kind e title bastam para decodificar")
    func minimalDecoding() throws {
        let snapshot = try decode(#"{"kind":"album","title":"Disco Inventado"}"#)
        #expect(snapshot == MusicSnapshot(kind: .album, title: "Disco Inventado"))
    }

    @Test("Chaves desconhecidas são ignoradas")
    func unknownKeysIgnored() throws {
        let snapshot = try decode(#"{"kind":"song","title":"Faixa","futuro":{"a":1},"outra":[1,2]}"#)
        #expect(snapshot.kind == .song)
        #expect(snapshot.title == "Faixa")
    }

    @Test("Sem kind a decodificação falha")
    func missingKindFails() {
        #expect(throws: DecodingError.self) { try decode(#"{"title":"Faixa"}"#) }
    }

    @Test("Ida e volta preserva todos os campos e não grava chaves nulas")
    func roundTrip() throws {
        let full = MusicSnapshot(
            kind: .song, catalogID: "123", storefront: "br", libraryPlaylistName: "Minha", libraryID: "L1",
            url: URL(string: "https://music.apple.com/br/song/123"), title: "Faixa", subtitle: "Artista",
            albumTitle: "Álbum", artworkTemplate: "https://exemplo.test/{w}x{h}.{f}", artworkFile: "capa.jpg",
            backgroundHex: "#f1e9dd", primaryTextHex: "#020201", secondaryTextHex: "#232321", trackCount: 3,
            releaseDate: "2026-01-02", duration: 12.5)
        let data = try JSONEncoder().encode(full)
        #expect(try JSONDecoder().decode(MusicSnapshot.self, from: data) == full)

        let minimal = try JSONEncoder().encode(MusicSnapshot(kind: .album, title: "A"))
        let object = try #require(JSONSerialization.jsonObject(with: minimal) as? [String: Any])
        #expect(Set(object.keys) == ["kind", "title"])
    }

    @Test("normalizedHex aceita formas válidas")
    func hexValid() {
        #expect(MusicSnapshot.normalizedHex("f1e9dd") == "#f1e9dd")
        #expect(MusicSnapshot.normalizedHex("#F1E9DD") == "#f1e9dd")
        #expect(MusicSnapshot.normalizedHex("  #AbCdEf \n") == "#abcdef")
    }

    @Test("normalizedHex rejeita o resto")
    func hexInvalid() {
        #expect(MusicSnapshot.normalizedHex(nil) == nil)
        #expect(MusicSnapshot.normalizedHex("") == nil)
        #expect(MusicSnapshot.normalizedHex("fff") == nil)
        #expect(MusicSnapshot.normalizedHex("f1e9d") == nil)
        #expect(MusicSnapshot.normalizedHex("f1e9ddd") == nil)
        #expect(MusicSnapshot.normalizedHex("gggggg") == nil)
        #expect(MusicSnapshot.normalizedHex("##f1e9dd") == nil)
    }

    @Test("artworkURL troca os marcadores")
    func artworkSubstitution() {
        var snapshot = MusicSnapshot(kind: .album, title: "A")
        snapshot.artworkTemplate = "https://is1-ssl.mzstatic.com/img/{w}x{h}bb.{f}"
        #expect(snapshot.artworkURL()?.absoluteString == "https://is1-ssl.mzstatic.com/img/600x600bb.jpg")
        #expect(snapshot.artworkURL(side: 120)?.absoluteString == "https://is1-ssl.mzstatic.com/img/120x120bb.jpg")
        #expect(snapshot.artworkURL(side: 0) == nil)
        #expect(snapshot.artworkURL(side: -5) == nil)
    }

    @Test("artworkURL sem molde, sem {w} ou com esquema não web devolve nil")
    func artworkInvalid() {
        var snapshot = MusicSnapshot(kind: .album, title: "A")
        #expect(snapshot.artworkURL() == nil)
        snapshot.artworkTemplate = "https://exemplo.test/fixa.jpg"
        #expect(snapshot.artworkURL() == nil)
        snapshot.artworkTemplate = "file:///tmp/{w}x{h}.{f}"
        #expect(snapshot.artworkURL() == nil)
        snapshot.artworkTemplate = "ftp://exemplo.test/{w}.{f}"
        #expect(snapshot.artworkURL() == nil)
    }

    @Test("artworkURL só aceita https em hosts da Apple")
    func artworkHostRestriction() {
        var snapshot = MusicSnapshot(kind: .album, title: "A")
        for allowed in ["mzstatic.com", "is1-ssl.mzstatic.com", "apple.com", "music.apple.com", "IS1-SSL.MZSTATIC.COM"] {
            snapshot.artworkTemplate = "https://\(allowed)/{w}x{h}.{f}"
            #expect(snapshot.artworkURL() != nil, "\(allowed)")
        }
        for denied in [
            "exemplo.test", "evilmzstatic.com", "mzstatic.com.evil.test", "apple.com.evil.test", "notapple.com", "192.168.0.1",
            "localhost", "mzstatic.com@evil.test",
        ] {
            snapshot.artworkTemplate = "https://\(denied)/{w}x{h}.{f}"
            #expect(snapshot.artworkURL() == nil, "\(denied)")
        }
        snapshot.artworkTemplate = "http://is1-ssl.mzstatic.com/{w}x{h}.{f}"
        #expect(snapshot.artworkURL() == nil)
    }

    @Test("canPlay exige id de catálogo, id local ou nome de playlist própria")
    func canPlay() {
        #expect(!MusicSnapshot(kind: .song, title: "A").canPlay)
        #expect(MusicSnapshot(kind: .song, catalogID: "1", title: "A").canPlay)
        #expect(MusicSnapshot(kind: .playlist, libraryID: "x", title: "A").canPlay)
        #expect(MusicSnapshot(kind: .playlist, libraryPlaylistName: "A", title: "A").canPlay)
    }

    @Test("dedupeKey usa catálogo, nome da playlist própria ou título e subtítulo")
    func dedupeKey() {
        #expect(MusicSnapshot(kind: .album, catalogID: "42", title: "A").dedupeKey == "album:catalog:42")
        #expect(
            MusicSnapshot(kind: .playlist, libraryPlaylistName: "Minha Lista", title: "Minha Lista").dedupeKey
                == "playlist:library:minha lista")
        #expect(
            MusicSnapshot(kind: .song, title: "Faixa", subtitle: "ARTISTA").dedupeKey == "song:title:faixa|artista")
        #expect(MusicSnapshot(kind: .song, title: "Faixa").dedupeKey == "song:title:faixa|")
        // O catálogo vence o nome da playlist própria.
        #expect(
            MusicSnapshot(kind: .playlist, catalogID: "pl.x", libraryPlaylistName: "N", title: "N").dedupeKey
                == "playlist:catalog:pl.x")
    }
}
