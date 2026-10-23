import Foundation
import MuralKit

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

/// Ponte com o Apple Music. Há uma versão real (MusicKit) e uma falsa para testes.
@MainActor
protocol MusicProviding: AnyObject {
    var access: MusicAccess { get }
    func requestAccess() async -> MusicAccess
    func eligibility() async -> MusicPlaybackEligibility
    var status: MusicPlayerStatus { get }
    /// Toca o item. Devolve o snapshot com o que foi resolvido (por exemplo, o `libraryID`
    /// de uma playlist própria achada pelo nome); sem novidade, o mesmo.
    func play(_ snapshot: MusicSnapshot, startingAt trackID: String?) async throws -> MusicSnapshot
    func resume() async throws
    func pause()
    func stop()
    func tracks(for snapshot: MusicSnapshot) async throws -> [MusicTrackRow]
    func catalogArtwork(for snapshot: MusicSnapshot) async -> MusicCatalogArtwork?
}
