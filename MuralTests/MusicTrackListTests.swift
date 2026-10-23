import Foundation
import MuralKit
import Testing

@testable import Mural

@Suite("Lista de faixas")
@MainActor
struct MusicTrackListTests {
    private let album = MusicSnapshot(kind: .album, catalogID: "1", title: "Álbum")

    private func rig(access: MusicAccess = .granted) -> (FakeMusic, MusicPlayback, MusicTrackList) {
        let fake = FakeMusic(arguments: [])
        fake.access = access
        return (fake, MusicPlayback(provider: fake), MusicTrackList())
    }

    @Test("Começa parada")
    func startsIdle() {
        #expect(rig().2.state == .idle)
    }

    @Test("Com acesso, carrega as faixas")
    func loadsRows() async {
        let (fake, playback, list) = rig()
        await list.load(album, playback: playback)
        #expect(list.state == .loaded(fake.trackRows))
    }

    @Test("Playlist também lista")
    func playlistLoads() async {
        let (fake, playback, list) = rig()
        await list.load(MusicSnapshot(kind: .playlist, catalogID: "2", title: "P"), playback: playback)
        #expect(list.state == .loaded(fake.trackRows))
    }

    @Test("Faixa e estação ficam escondidas")
    func songAndStationAreHidden() async {
        let (_, playback, list) = rig()
        await list.load(MusicSnapshot(kind: .song, catalogID: "3", title: "S"), playback: playback)
        #expect(list.state == .hidden)
        await list.load(MusicSnapshot(kind: .station, catalogID: "4", title: "E"), playback: playback)
        #expect(list.state == .hidden)
    }

    @Test("Sem decisão de acesso pede acesso")
    func needsAccess() async {
        let (_, playback, list) = rig(access: .notDetermined)
        await list.load(album, playback: playback)
        #expect(list.state == .needsAccess)
    }

    @Test("Acesso negado ou restrito")
    func denied() async {
        for access in [MusicAccess.denied, .restricted] {
            let (_, playback, list) = rig(access: access)
            await list.load(album, playback: playback)
            #expect(list.state == .denied)
        }
    }

    @Test("allowAccess pede a permissão e carrega")
    func allowAccessLoads() async {
        let (fake, playback, list) = rig(access: .notDetermined)
        fake.accessAfterRequest = .granted
        await list.allowAccess(album, playback: playback)
        #expect(fake.requestAccessCount == 1)
        #expect(list.state == .loaded(fake.trackRows))
    }

    @Test("allowAccess recusado vira denied")
    func allowAccessDenied() async {
        let (fake, playback, list) = rig(access: .notDetermined)
        fake.accessAfterRequest = .denied
        await list.allowAccess(album, playback: playback)
        #expect(list.state == .denied)
    }

    @Test("Lista vazia vira unavailable")
    func emptyIsUnavailable() async {
        let (fake, playback, list) = rig()
        fake.trackRows = []
        await list.load(album, playback: playback)
        #expect(list.state == .unavailable)
    }

    @Test("Erro vira unavailable")
    func errorIsUnavailable() async {
        let (fake, playback, list) = rig()
        fake.tracksError = MusicPlaybackError.failed
        await list.load(album, playback: playback)
        #expect(list.state == .unavailable)
    }

    @Test("O pedido mais novo vence, mesmo se o antigo terminar depois")
    func newestRequestWins() async {
        let (fake, playback, list) = rig()
        fake.tracksDelay = ["Lento": .milliseconds(150)]
        fake.tracksByTitle = ["Lento": [MusicTrackRow(id: "x", number: 1, title: "Velha", artist: nil, duration: nil)]]
        let slow = MusicSnapshot(kind: .album, catalogID: "5", title: "Lento")
        async let first: Void = list.load(slow, playback: playback)
        try? await Task.sleep(for: .milliseconds(30))
        await list.load(album, playback: playback)
        await first
        #expect(list.state == .loaded(fake.trackRows))
    }
}
