import Foundation
import MuralKit
import MusicKit

/// Situação da permissão de acesso ao Apple Music.
enum MusicAccess: Equatable, Sendable {
    case notDetermined
    case denied
    case restricted
    case granted
}

/// O que a conta pode fazer com o catálogo do Apple Music.
enum MusicPlaybackEligibility: Equatable, Sendable {
    case canPlay
    /// Sem assinatura, mas pode assinar.
    case canSubscribe
    case cannotPlay
}

/// Estado do tocador do Mural.
enum MusicPlayerStatus: Equatable, Sendable {
    case stopped
    case playing
    case paused
}

/// Uma faixa (ou entrada de playlist) para listar e tocar a partir dela.
struct MusicTrackRow: Identifiable, Hashable, Sendable {
    let id: String
    let number: Int
    let title: String
    let artist: String?
    let duration: TimeInterval?
}

/// Motivos pelos quais não foi possível tocar.
enum MusicPlaybackError: Error, Equatable {
    case notFound
    case ambiguousPlaylist
    case notPlayable
    case failed
}

/// Capa e cores de um item do catálogo.
struct MusicCatalogArtwork: Equatable, Sendable {
    var url: URL
    var backgroundHex: String?
    var primaryTextHex: String?
    var secondaryTextHex: String?
}

/// A entrada que o tocador está tocando agora (faixa, vídeo ou estação).
struct MusicNowPlaying: Equatable, Sendable {
    /// Identifica a entrada na fila; muda a cada faixa.
    let entryID: String
    let title: String
    let subtitle: String?
    /// `nil` quando o tocador não informa (estações).
    let duration: TimeInterval?
    let artwork: Artwork?
}

/// Ponte com o Apple Music. Há uma versão real (MusicKit) e uma falsa para testes.
@MainActor
protocol MusicProviding: AnyObject {
    var access: MusicAccess { get }
    func requestAccess() async -> MusicAccess
    func eligibility() async -> MusicPlaybackEligibility
    var status: MusicPlayerStatus { get }
    /// A entrada atual da fila; `nil` parado ou sem fila.
    var nowPlaying: MusicNowPlaying? { get }
    /// Posição na entrada atual, em segundos; 0 enquanto o tocador não foi usado.
    var playbackTime: TimeInterval { get }
    /// Aleatório da fila; `nil` quando o tocador não o oferece (estações) ou ainda não foi usado.
    var shuffle: MusicShuffle? { get }
    /// Repetição da fila; `nil` quando o tocador não a oferece ou ainda não foi usado.
    var repeatMode: MusicRepeat? { get }
    /// Chamado quando a fila acaba ou o sistema para o tocador. Nunca depois de `stop()`.
    var onPlaybackEnded: (@MainActor () -> Void)? { get set }
    /// Toca o item. Devolve o snapshot com o que foi resolvido (por exemplo, o `libraryID`
    /// de uma playlist própria achada pelo nome); sem novidade, o mesmo.
    func play(_ snapshot: MusicSnapshot, startingAt trackID: String?) async throws -> MusicSnapshot
    func resume() async throws
    func pause()
    func stop()
    func skipToNext() async throws
    /// Faixa anterior; com mais de 3 s tocados, volta ao início da atual (como no iPhone).
    func skipToPrevious() async throws
    func setShuffle(_ mode: MusicShuffle)
    func setRepeat(_ mode: MusicRepeat)
    /// Leva a reprodução para esta posição, em segundos, dentro da entrada atual.
    func seek(to time: TimeInterval)
    func tracks(for snapshot: MusicSnapshot) async throws -> [MusicTrackRow]
    func catalogArtwork(for snapshot: MusicSnapshot) async -> MusicCatalogArtwork?
    /// Procura músicas, álbuns e playlists no catálogo do Apple Music.
    func search(term: String) async throws -> [MusicSnapshot]
}
