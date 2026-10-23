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
    private(set) var status: MusicPlayerStatus = .stopped

    // Registro das chamadas.
    private(set) var requestAccessCount = 0
    private(set) var played: [(MusicSnapshot, String?)] = []
    private(set) var pauseCount = 0
    private(set) var stopCount = 0
    private(set) var resumeCount = 0

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
        if let playError { throw playError }
        status = .playing
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
    }

    func tracks(for snapshot: MusicSnapshot) async throws -> [MusicTrackRow] {
        snapshot.kind == .album || snapshot.kind == .playlist ? trackRows : []
    }

    func catalogArtwork(for snapshot: MusicSnapshot) async -> MusicCatalogArtwork? { artwork }
}
