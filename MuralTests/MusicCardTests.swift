import AppKit
import MuralKit
import SwiftUI
import Testing

@testable import Mural

/// Textos do cartão de música, cor das capas, cópia para a área de transferência e leque da pasta.
@Suite("Cartão de música")
@MainActor
struct MusicCardTests {
    private func music(_ kind: MusicItemKind, trackCount: Int? = nil, duration: TimeInterval? = nil) -> MusicSnapshot {
        MusicSnapshot(kind: kind, title: "Título", subtitle: "Artista", trackCount: trackCount, duration: duration)
    }

    @Test("A linha de detalhe de cada tipo, com singular, plural e sem dados")
    func detailLines() {
        #expect(music(.album, trackCount: 12).detailLine == "Álbum · 12 faixas")
        #expect(music(.album, trackCount: 1).detailLine == "Álbum · 1 faixa")
        #expect(music(.album).detailLine == "Álbum")
        #expect(music(.song, duration: 213).detailLine == "Música · 3:33")
        #expect(music(.song, duration: 9).detailLine == "Música · 0:09")
        #expect(music(.song, duration: 3_725).detailLine == "Música · 1:02:05")
        #expect(music(.song).detailLine == "Música")
        #expect(music(.playlist, trackCount: 30).detailLine == "Playlist")
        #expect(music(.station).detailLine == "Estação")
    }

    @Test("Nomes e símbolos dos tipos")
    func namesAndSymbols() {
        #expect(MusicItemKind.allCases.map(\.displayName) == ["Álbum", "Música", "Playlist", "Estação"])
        #expect(MusicItemKind.allCases.map(\.symbol) == ["square.stack", "music.note", "music.note.list", "dot.radiowaves.left.and.right"])
    }

    @Test("Ano de lançamento vem dos quatro primeiros dígitos")
    func releaseYear() {
        var snapshot = music(.album)
        #expect(snapshot.releaseYear == nil)
        snapshot.releaseDate = "1969-09-26"
        #expect(snapshot.releaseYear == "1969")
        snapshot.releaseDate = "abc"
        #expect(snapshot.releaseYear == nil)
    }

    @Test("Cor em #rrggbb; texto inválido não vira cor")
    func hexColor() {
        #expect(Color(muralHex: "#1f3a5f") != nil)
        #expect(Color(muralHex: "FFFFFF") != nil)
        #expect(Color(muralHex: nil) == nil)
        #expect(Color(muralHex: "") == nil)
        #expect(Color(muralHex: "#12345") == nil)
        #expect(Color(muralHex: "#gggggg") == nil)
        #expect(Color(muralHex: "vermelho") == nil)
    }

    // MARK: Área de transferência

    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("MuralMusicTests-\(UUID().uuidString)"))
    }

    private func makeModel() -> BoardModel {
        BoardModel(
            store: BoardStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("MuralMusicExport-\(UUID().uuidString)")),
            seedIfEmpty: false)
    }

    @Test("Música com endereço copia como link: endereço, título e texto")
    func copyWithURL() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let url = try #require(URL(string: "https://music.apple.com/br/album/abbey-road/1"))
        let snapshot = MusicSnapshot(kind: .album, url: url, title: "Abbey Road", subtitle: "The Beatles")
        let item = BoardItem(kind: .music, title: "Abbey Road", music: snapshot)

        PasteboardExporter.copy(item, from: makeModel(), to: pasteboard)

        #expect(pasteboard.pasteboardItems?.count == 1)
        #expect(pasteboard.string(forType: .URL) == url.absoluteString)
        #expect(pasteboard.string(forType: NSPasteboard.PasteboardType("public.url-name")) == "Abbey Road")
        #expect(pasteboard.string(forType: .string) == url.absoluteString)
    }

    @Test("Música sem endereço copia título e artista, sem linha vazia")
    func copyWithoutURL() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let model = makeModel()
        let item = BoardItem(kind: .music, title: "Something", music: MusicSnapshot(kind: .song, title: "Something", subtitle: "The Beatles"))

        PasteboardExporter.copy(item, from: model, to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "Something\nThe Beatles")
        #expect(pasteboard.string(forType: .URL) == nil)

        let bare = BoardItem(kind: .music, title: "Minha playlist", music: MusicSnapshot(kind: .playlist, title: "Minha playlist"))
        PasteboardExporter.copy(bare, from: model, to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "Minha playlist")
    }

    // MARK: Leque da pasta

    @Test("Música espia pela capa guardada; sem ela, pelo título")
    func folderPeekUsesArtwork() {
        let withArt = BoardItem(kind: .music, title: "Com capa", music: MusicSnapshot(kind: .album, title: "Com capa", artworkFile: "capa.jpg"))
        let without = BoardItem(kind: .music, title: "Sem capa", music: MusicSnapshot(kind: .album, title: "Sem capa"))
        let artwork = URL(fileURLWithPath: "/tmp/LinkPreviews/capa.jpg")

        let peeks = FolderPeekItem.latest(
            [withArt, without], fileURL: { _ in nil },
            linkPreviewURL: { $0.music?.artworkFile == "capa.jpg" ? artwork : nil })

        #expect(peeks.map(\.kind) == [.music, .music])
        #expect(peeks.map(\.fileURL) == [artwork, nil])
    }

    @Test("linkPreviewURL lê a capa da música na pasta de prévias")
    func peekURLReadsArtworkFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MuralMusicPeek-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data([1]).write(to: directory.appendingPathComponent("capa.jpg"))
        let files = LinkPreviewFiles(directory: directory)
        let item = BoardItem(kind: .music, title: "x", music: MusicSnapshot(kind: .album, title: "x", artworkFile: "capa.jpg"))
        #expect(FolderPeekItem.linkPreviewURL(of: item, in: files) == files.existingURL(for: "capa.jpg"))
        #expect(FolderPeekItem.linkPreviewURL(of: item, in: files) != nil)
        #expect(FolderPeekItem.linkPreviewURL(of: item, in: nil) == nil)
    }
}
