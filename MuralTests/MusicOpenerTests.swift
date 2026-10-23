import Foundation
import MuralKit
import Testing

@testable import Mural

@Suite("Abrir no Música")
@MainActor
struct MusicOpenerTests {
    private let link = URL(string: "https://music.apple.com/br/album/x/1")!
    private let app = URL(fileURLWithPath: "/System/Applications/Music.app")

    @Test("Com endereço e app, abre o endereço no app")
    func urlInApp() {
        let music = MusicSnapshot(kind: .album, url: link, title: "A")
        #expect(MusicOpener.target(for: music, musicAppURL: app) == .urlInMusicApp(link, app: app))
    }

    @Test("Sem endereço, abre só o app")
    func appOnly() {
        let music = MusicSnapshot(kind: .playlist, title: "A")
        #expect(MusicOpener.target(for: music, musicAppURL: app) == .musicApp(app))
    }

    @Test("Sem o app, abre o endereço no navegador")
    func browserFallback() {
        let music = MusicSnapshot(kind: .album, url: link, title: "A")
        #expect(MusicOpener.target(for: music, musicAppURL: nil) == .browser(link))
    }

    @Test("Sem endereço nem app, não abre nada")
    func nothing() {
        #expect(MusicOpener.target(for: MusicSnapshot(kind: .song, title: "A"), musicAppURL: nil) == .nothing)
    }
}
