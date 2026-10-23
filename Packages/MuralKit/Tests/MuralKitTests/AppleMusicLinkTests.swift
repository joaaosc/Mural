import Foundation
import Testing

@testable import MuralKit

@Suite("Endereços do Apple Music")
struct AppleMusicLinkTests {
    private func read(_ text: String, title: String? = nil) throws -> MusicSnapshot? {
        AppleMusicLink.snapshot(from: try #require(URL(string: text)), title: title)
    }

    @Test("Álbum com loja e nome; l= é removido da url")
    func albumWithStorefront() throws {
        let snapshot = try #require(
            try read("https://music.apple.com/br/album/disco-inventado/1234567890?l=en-GB"))
        #expect(snapshot.kind == .album)
        #expect(snapshot.catalogID == "1234567890")
        #expect(snapshot.storefront == "br")
        #expect(snapshot.title == "Disco inventado")
        #expect(snapshot.url?.absoluteString == "https://music.apple.com/br/album/disco-inventado/1234567890")
    }

    @Test("Loja é guardada em minúsculas")
    func storefrontLowercased() throws {
        #expect(try read("https://music.apple.com/US/album/x/1")?.storefront == "us")
    }

    @Test("Álbum sem nome usa o título padrão")
    func albumWithoutName() throws {
        let snapshot = try #require(try read("https://music.apple.com/br/album/1234567890"))
        #expect(snapshot.kind == .album)
        #expect(snapshot.title == "Álbum")
    }

    @Test("Álbum com ?i= vira faixa e mantém o i na url")
    func albumWithTrackParameter() throws {
        let snapshot = try #require(
            try read("https://music.apple.com/br/album/disco/111?i=222&l=pt"))
        #expect(snapshot.kind == .song)
        #expect(snapshot.catalogID == "222")
        #expect(snapshot.url?.absoluteString == "https://music.apple.com/br/album/disco/111?i=222")
    }

    @Test("i não numérico é ignorado e o álbum prevalece")
    func nonNumericTrackParameter() throws {
        let snapshot = try #require(try read("https://music.apple.com/br/album/disco/111?i=abc"))
        #expect(snapshot.kind == .album)
        #expect(snapshot.catalogID == "111")
    }

    @Test("Caminho /song/")
    func song() throws {
        let snapshot = try #require(try read("https://music.apple.com/us/song/faixa-nova/999"))
        #expect(snapshot.kind == .song)
        #expect(snapshot.catalogID == "999")
        #expect(snapshot.title == "Faixa nova")
        let bare = try #require(try read("https://music.apple.com/us/song/999"))
        #expect(bare.title == "Música")
    }

    @Test("Playlist pl. e pl.u-")
    func playlists() throws {
        let editorial = try #require(try read("https://music.apple.com/br/playlist/hits/pl.abc123"))
        #expect(editorial.kind == .playlist)
        #expect(editorial.catalogID == "pl.abc123")
        let user = try #require(try read("https://music.apple.com/br/playlist/minha/pl.u-AbC123"))
        #expect(user.catalogID == "pl.u-AbC123")
        #expect(try read("https://music.apple.com/br/playlist/pl.abc123")?.title == "Playlist")
        #expect(try read("https://music.apple.com/br/playlist/x/abc123") == nil)
    }

    @Test("Estação ra.")
    func station() throws {
        let snapshot = try #require(try read("https://music.apple.com/br/station/radio/ra.985488283"))
        #expect(snapshot.kind == .station)
        #expect(snapshot.catalogID == "ra.985488283")
        #expect(snapshot.title == "Radio")
        #expect(try read("https://music.apple.com/br/station/ra.1")?.title == "Estação")
    }

    @Test("Sem loja")
    func withoutStorefront() throws {
        let snapshot = try #require(try read("https://music.apple.com/album/disco/123"))
        #expect(snapshot.storefront == nil)
        #expect(snapshot.catalogID == "123")
    }

    @Test("Esquema music:// vira https na url")
    func musicScheme() throws {
        let snapshot = try #require(try read("music://music.apple.com/br/album/disco/123"))
        #expect(snapshot.kind == .album)
        #expect(snapshot.url?.absoluteString == "https://music.apple.com/br/album/disco/123")
    }

    @Test("Hosts geo. e embed.")
    func otherHosts() throws {
        #expect(try read("https://geo.music.apple.com/br/album/disco/123")?.catalogID == "123")
        #expect(try read("https://embed.music.apple.com/br/album/disco/123")?.catalogID == "123")
        #expect(try read("https://beta.music.apple.com/br/album/disco/123")?.catalogID == "123")
    }

    @Test("Forma antiga itmss://itunes.com com p e i vira faixa")
    func legacySong() throws {
        let snapshot = try #require(try read("itmss://itunes.com/album?p=1000000001&i=1000000002"))
        #expect(snapshot.kind == .song)
        #expect(snapshot.catalogID == "1000000002")
        #expect(snapshot.storefront == nil)
        #expect(snapshot.url?.absoluteString == "https://music.apple.com/album/1000000001?i=1000000002")
        #expect(snapshot.title == "Música")
    }

    @Test("Forma antiga só com p vira álbum; só com i vira faixa sem álbum")
    func legacyAlbum() throws {
        let album = try #require(try read("itmss://itunes.com/album?p=1000000001"))
        #expect(album.kind == .album)
        #expect(album.catalogID == "1000000001")
        #expect(album.url?.absoluteString == "https://music.apple.com/album/1000000001")
        let song = try #require(try read("itms://itunes.apple.com/album?i=77"))
        #expect(song.url?.absoluteString == "https://music.apple.com/song/77")
        #expect(try read("itmss://itunes.com/album?p=abc") == nil)
        #expect(try read("itmss://itunes.com/artist?p=1") == nil)
    }

    @Test("Casos rejeitados")
    func rejected() throws {
        #expect(try read("https://music.apple.com/br/artist/alguem/123") == nil)
        #expect(try read("https://music.apple.com/br/music-video/clipe/123") == nil)
        #expect(try read("https://music.apple.com/library/playlist/p.abc123") == nil)
        #expect(try read("https://music.apple.com/br/album/disco/abc") == nil)
        #expect(try read("https://music.apple.com.evil.com/br/album/disco/123") == nil)
        #expect(try read("https://evil.com/music.apple.com/br/album/disco/123") == nil)
        #expect(try read("ftp://music.apple.com/br/album/disco/123") == nil)
        #expect(try read("https://music.apple.com/br/album") == nil)
        #expect(try read("https://music.apple.com/") == nil)
    }

    @Test("Título explícito vence o nome do caminho e é aparado")
    func explicitTitle() throws {
        let url = "https://music.apple.com/br/album/nome-do-caminho/123"
        #expect(try read(url, title: "  Meu Título ")?.title == "Meu Título")
        #expect(try read(url, title: "   ")?.title == "Nome do caminho")
        #expect(try read(url)?.title == "Nome do caminho")
    }
}
