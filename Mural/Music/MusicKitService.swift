import Combine
import CoreGraphics
import Foundation
import MuralKit
import MusicKit
import Observation

/// Ponte real com o Apple Music, pelo MusicKit. O "Tocando agora" fica por conta do `ApplicationMusicPlayer`.
@MainActor
@Observable
final class MusicKitService: MusicProviding {
    /// Item já resolvido, para não pedir de novo.
    private enum Resolved {
        case album(Album)
        case song(Song)
        case playlist(Playlist)
        case station(Station)
    }

    private(set) var status: MusicPlayerStatus = .stopped
    @ObservationIgnored nonisolated(unsafe) private let player = ApplicationMusicPlayer.shared
    @ObservationIgnored private var resolved: [String: Resolved] = [:]
    @ObservationIgnored private var observation: Task<Void, Never>?

    deinit { observation?.cancel() }

    /// Passa a acompanhar o tocador só no primeiro uso: abrir um mural com música não acorda o Apple Music.
    private func observeIfNeeded() {
        guard observation == nil else { return }
        observation = Task { [weak self] in
            guard let player = self?.player else { return }
            for await _ in player.state.objectWillChange.values {
                // O aviso chega antes da mudança.
                await Task.yield()
                guard let self else { return }
                self.status = Self.map(player.state.playbackStatus)
            }
        }
    }

    private static func map(_ status: MusicPlayer.PlaybackStatus) -> MusicPlayerStatus {
        switch status {
        case .playing: .playing
        case .paused, .interrupted: .paused
        default: .stopped
        }
    }

    // MARK: Acesso

    var access: MusicAccess {
        switch MusicAuthorization.currentStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        case .authorized: .granted
        @unknown default: .denied
        }
    }

    func requestAccess() async -> MusicAccess {
        _ = await MusicAuthorization.request()
        return access
    }

    func eligibility() async -> MusicPlaybackEligibility {
        guard let subscription = try? await MusicSubscription.current else { return .cannotPlay }
        if subscription.canPlayCatalogContent { return .canPlay }
        return subscription.canBecomeSubscriber ? .canSubscribe : .cannotPlay
    }

    // MARK: Tocar

    func play(_ snapshot: MusicSnapshot, startingAt trackID: String?) async throws -> MusicSnapshot {
        var snapshot = snapshot
        let item: Resolved
        do {
            (item, snapshot) = try await resolve(snapshot)
        } catch let error as MusicPlaybackError {
            throw error
        } catch {
            throw MusicPlaybackError.failed
        }
        observeIfNeeded()
        do {
            switch item {
            case .album(let album):
                // As faixas só são pedidas para começar de uma delas.
                if let trackID, let full = try? await album.with([.tracks]),
                    let track = full.tracks?.first(where: { $0.id.rawValue == trackID })
                {
                    player.queue = ApplicationMusicPlayer.Queue(album: full, startingAt: track)
                } else {
                    player.queue = [album]
                }
            case .playlist(let playlist):
                if let trackID, let full = try? await playlist.with([.entries]),
                    let entry = full.entries?.first(where: { $0.id.rawValue == trackID })
                {
                    player.queue = ApplicationMusicPlayer.Queue(playlist: full, startingAt: entry)
                } else {
                    player.queue = [playlist]
                }
            case .song(let song): player.queue = [song]
            case .station(let station): player.queue = [station]
            }
            try await player.play()
        } catch {
            throw MusicPlaybackError.failed
        }
        return snapshot
    }

    func resume() async throws {
        observeIfNeeded()
        do { try await player.play() } catch { throw MusicPlaybackError.failed }
    }

    func pause() { player.pause() }

    func stop() { player.stop() }

    // MARK: Resolver

    private func resolve(_ snapshot: MusicSnapshot) async throws -> (Resolved, MusicSnapshot) {
        if let cached = resolved[snapshot.dedupeKey] { return (cached, snapshot) }
        var snapshot = snapshot
        let item: Resolved
        if let catalogID = snapshot.catalogID {
            let id = MusicItemID(catalogID)
            switch snapshot.kind {
            case .album:
                let request = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: id)
                guard let found = try await request.response().items.first else { throw MusicPlaybackError.notFound }
                item = .album(found)
            case .song:
                let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: id)
                guard let found = try await request.response().items.first else { throw MusicPlaybackError.notFound }
                item = .song(found)
            case .playlist:
                let request = MusicCatalogResourceRequest<Playlist>(matching: \.id, equalTo: id)
                guard let found = try await request.response().items.first else { throw MusicPlaybackError.notFound }
                item = .playlist(found)
            case .station:
                let request = MusicCatalogResourceRequest<Station>(matching: \.id, equalTo: id)
                guard let found = try await request.response().items.first else { throw MusicPlaybackError.notFound }
                item = .station(found)
            }
        } else if snapshot.kind == .playlist, snapshot.libraryID != nil || snapshot.libraryPlaylistName != nil {
            let playlist = try await libraryPlaylist(for: snapshot)
            snapshot.libraryID = playlist.id.rawValue
            item = .playlist(playlist)
        } else {
            throw MusicPlaybackError.notPlayable
        }
        // Pequeno: guarda só os últimos itens.
        if resolved.count >= 20 { resolved.removeAll() }
        resolved[snapshot.dedupeKey] = item
        return (item, snapshot)
    }

    private func libraryPlaylist(for snapshot: MusicSnapshot) async throws -> Playlist {
        if let libraryID = snapshot.libraryID {
            var request = MusicLibraryRequest<Playlist>()
            request.filter(matching: \.id, equalTo: MusicItemID(libraryID))
            if let found = try await request.response().items.first { return found }
        }
        guard let name = snapshot.libraryPlaylistName else { throw MusicPlaybackError.notFound }
        var request = MusicLibraryRequest<Playlist>()
        request.filter(matching: \.name, contains: name)
        let exact = try await request.response().items.filter { $0.name == name }
        switch exact.count {
        case 0: throw MusicPlaybackError.notFound
        case 1: return exact[0]
        default: throw MusicPlaybackError.ambiguousPlaylist
        }
    }

    // MARK: Faixas e capa

    func tracks(for snapshot: MusicSnapshot) async throws -> [MusicTrackRow] {
        guard snapshot.kind == .album || snapshot.kind == .playlist else { return [] }
        let item: Resolved
        do { item = try await resolve(snapshot).0 } catch let error as MusicPlaybackError { throw error } catch {
            throw MusicPlaybackError.failed
        }
        do {
            switch item {
            case .album(let album):
                let tracks = try await album.with([.tracks]).tracks ?? []
                return tracks.enumerated().map { index, track in
                    MusicTrackRow(
                        id: track.id.rawValue, number: index + 1, title: track.title,
                        artist: track.artistName, duration: track.duration)
                }
            case .playlist(let playlist):
                let full = try await playlist.with([.tracks, .entries])
                if let entries = full.entries, !entries.isEmpty {
                    return entries.enumerated().map { index, entry in
                        MusicTrackRow(
                            id: entry.id.rawValue, number: index + 1, title: entry.title,
                            artist: entry.artistName, duration: entry.duration)
                    }
                }
                return (full.tracks ?? []).enumerated().map { index, track in
                    MusicTrackRow(
                        id: track.id.rawValue, number: index + 1, title: track.title,
                        artist: track.artistName, duration: track.duration)
                }
            case .song, .station:
                return []
            }
        } catch {
            throw MusicPlaybackError.failed
        }
    }

    func catalogArtwork(for snapshot: MusicSnapshot) async -> MusicCatalogArtwork? {
        guard snapshot.catalogID != nil, let item = try? await resolve(snapshot).0 else { return nil }
        let artwork: Artwork?
        switch item {
        case .album(let value): artwork = value.artwork
        case .song(let value): artwork = value.artwork
        case .playlist(let value): artwork = value.artwork
        case .station(let value): artwork = value.artwork
        }
        guard let artwork, let url = artwork.url(width: 600, height: 600),
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        return MusicCatalogArtwork(
            url: url, backgroundHex: Self.hex(artwork.backgroundColor),
            primaryTextHex: Self.hex(artwork.primaryTextColor),
            secondaryTextHex: Self.hex(artwork.secondaryTextColor))
    }

    /// `#rrggbb` em sRGB; `nil` sem cor ou sem como converter.
    private static func hex(_ color: CGColor?) -> String? {
        guard let color, let space = CGColorSpace(name: CGColorSpace.sRGB),
            let converted = color.converted(to: space, intent: .defaultIntent, options: nil),
            let components = converted.components, components.count >= 3
        else { return nil }
        let bytes = components.prefix(3).map { Int((min(max($0, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", bytes[0], bytes[1], bytes[2])
    }
}
