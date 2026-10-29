import Foundation
import MuralKit
import Observation

/// Apple Music em memória, para testes e para os testes de interface.
@MainActor
@Observable
final class FakeMusic: MusicProviding {
    var access: MusicAccess
    var eligibilityResult: MusicPlaybackEligibility
    /// Valor que `access` assume depois de `requestAccess()` quando ainda não decidido.
    var accessAfterRequest: MusicAccess = .granted
    var playError: MusicPlaybackError?
    /// Devolvido por `play` em playlist própria sem `libraryID`.
    var resolvedLibraryID: String?
    var trackRows: [MusicTrackRow] = (1...3).map {
        MusicTrackRow(id: "faixa-\($0)", number: $0, title: "Faixa \($0)", artist: "Artista", duration: 180)
    }
    var artwork: MusicCatalogArtwork?
    /// Faz `tracks(for:)` falhar.
    var tracksError: (any Error)?
    /// Faixas e espera por título de cartão, para simular respostas fora de ordem; sem entrada, vale `trackRows`.
    var tracksByTitle: [String: [MusicTrackRow]] = [:]
    var tracksDelay: [String: Duration] = [:]
    private(set) var status: MusicPlayerStatus = .stopped
    private(set) var nowPlaying: MusicNowPlaying?
    var onPlaybackEnded: (@MainActor () -> Void)?
    /// Posição simulada na entrada atual.
    var playbackTime: TimeInterval = 0
    /// Aleatório e repetição simulados; `nil` simula um tocador que não os oferece.
    var shuffle: MusicShuffle? = .off
    var repeatMode: MusicRepeat? = MusicRepeat.none
    /// Faz `skipToNext` e `skipToPrevious` falharem.
    var skipError: MusicPlaybackError?
    /// Espera dentro de `play`, para simular o carregamento.
    var playDelay: Duration?

    /// A fila simulada: título, subtítulo e duração de cada entrada, e a posição atual.
    private var entries: [(id: String, title: String, subtitle: String?, duration: TimeInterval?)] = []
    private var entryIndex = 0

    // Registro das chamadas.
    private(set) var requestAccessCount = 0
    private(set) var played: [(MusicSnapshot, String?)] = []
    private(set) var pauseCount = 0
    private(set) var stopCount = 0
    private(set) var resumeCount = 0
    private(set) var skipNextCount = 0
    private(set) var skipPreviousCount = 0
    private(set) var shuffleCalls: [MusicShuffle] = []
    private(set) var repeatCalls: [MusicRepeat] = []
    private(set) var seekCalls: [TimeInterval] = []

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        access = arguments.contains("-fakeMusicDenied") ? .denied : .granted
        eligibilityResult = arguments.contains("-fakeMusicNoSubscription") ? .canSubscribe : .canPlay
    }

    func requestAccess() async -> MusicAccess {
        requestAccessCount += 1
        if access == .notDetermined { access = accessAfterRequest }
        return access
    }

    func eligibility() async -> MusicPlaybackEligibility { eligibilityResult }

    func play(_ snapshot: MusicSnapshot, startingAt trackID: String?) async throws -> MusicSnapshot {
        played.append((snapshot, trackID))
        if let playDelay { try? await Task.sleep(for: playDelay) }
        if let playError { throw playError }
        status = .playing
        buildEntries(for: snapshot, startingAt: trackID)
        var result = snapshot
        if snapshot.kind == .playlist, snapshot.libraryID == nil, snapshot.catalogID == nil, let resolvedLibraryID {
            result.libraryID = resolvedLibraryID
        }
        return result
    }

    func resume() async throws {
        resumeCount += 1
        status = .playing
    }

    func pause() {
        pauseCount += 1
        status = .paused
    }

    func stop() {
        stopCount += 1
        status = .stopped
        entries = []
        nowPlaying = nil
    }

    func skipToNext() async throws {
        skipNextCount += 1
        if let skipError { throw skipError }
        if repeatMode == .one, entries.indices.contains(entryIndex) {
            playbackTime = 0
        } else if entryIndex + 1 < entries.count {
            entryIndex += 1
            playbackTime = 0
            refreshNowPlaying()
        } else if repeatMode == .all, !entries.isEmpty {
            entryIndex = 0
            playbackTime = 0
            refreshNowPlaying()
        } else {
            finishQueue()
        }
    }

    func skipToPrevious() async throws {
        skipPreviousCount += 1
        if let skipError { throw skipError }
        if playbackTime > 3 {
            playbackTime = 0
            return
        }
        entryIndex = max(entryIndex - 1, 0)
        playbackTime = 0
        refreshNowPlaying()
    }

    func setShuffle(_ mode: MusicShuffle) {
        shuffleCalls.append(mode)
        guard shuffle != nil else { return }
        shuffle = mode
    }

    func setRepeat(_ mode: MusicRepeat) {
        repeatCalls.append(mode)
        guard repeatMode != nil else { return }
        repeatMode = mode
    }

    func seek(to time: TimeInterval) {
        seekCalls.append(time)
        var target = max(time, 0)
        if let duration = nowPlaying?.duration { target = min(target, duration) }
        playbackTime = target
    }

    /// Simula o fim da fila (ou uma parada do sistema): para, limpa a entrada e avisa.
    func finishQueue() {
        status = .stopped
        entries = []
        nowPlaying = nil
        playbackTime = 0
        onPlaybackEnded?()
    }

    private func buildEntries(for snapshot: MusicSnapshot, startingAt trackID: String?) {
        entryIndex = 0
        playbackTime = 0
        switch snapshot.kind {
        case .album, .playlist:
            let rows = tracksByTitle[snapshot.title] ?? trackRows
            entries = rows.map { ($0.id, $0.title, $0.artist, $0.duration) }
            if let trackID, let index = rows.firstIndex(where: { $0.id == trackID }) { entryIndex = index }
        case .song:
            entries = [("entrada-\(snapshot.title)", snapshot.title, snapshot.subtitle, 180)]
        case .station:
            entries = [("entrada-\(snapshot.title)", snapshot.title, snapshot.subtitle, nil)]
        }
        refreshNowPlaying()
    }

    private func refreshNowPlaying() {
        guard entries.indices.contains(entryIndex) else {
            nowPlaying = nil
            return
        }
        let entry = entries[entryIndex]
        nowPlaying = MusicNowPlaying(
            entryID: entry.id, title: entry.title, subtitle: entry.subtitle, duration: entry.duration, artwork: nil)
    }

    func tracks(for snapshot: MusicSnapshot) async throws -> [MusicTrackRow] {
        if let delay = tracksDelay[snapshot.title] { try? await Task.sleep(for: delay) }
        if let tracksError { throw tracksError }
        guard snapshot.kind == .album || snapshot.kind == .playlist else { return [] }
        return tracksByTitle[snapshot.title] ?? trackRows
    }

    func catalogArtwork(for snapshot: MusicSnapshot) async -> MusicCatalogArtwork? { artwork }
}
