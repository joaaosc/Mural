import Foundation
import MuralKit
import MusicKit

/// O que o miniplayer e o painel da barra de menus mostram sobre a música que toca.
struct NowPlayingSummary: Equatable {
    let itemID: UUID
    let boardID: BoardID
    let route: BoardRoute
    /// Título da entrada atual; sem ela, o do cartão.
    let title: String
    /// Artista da entrada atual; sem ele, o do cartão.
    let artist: String?
    let boardTitle: String
    let cardTitle: String
    let phase: MusicCardPhase
    let canSkipBackward: Bool
    /// `nil` quando o tocador não informa (estações).
    let duration: TimeInterval?
    /// `nil` quando o tocador não oferece aleatório (estações) ou nada se pode mudar.
    let shuffle: MusicShuffle?
    let repeatMode: MusicRepeat?
    let canSeek: Bool
    let artwork: Artwork?
    /// A capa e as cores do cartão, para quando o tocador não traz capa.
    let fallbackMusic: MusicSnapshot

    /// De onde vem a música, para a linha de origem.
    var sourceLine: String { "No mural \(boardTitle) · \(cardTitle)" }
}

extension MusicPlayback {
    /// O resumo do que toca. Os nomes do mural e do cartão vêm da aba aberta, quando há; senão, dos guardados.
    func summary(in tabs: MuralTabs) -> NowPlayingSummary? {
        guard let source else { return nil }
        let tab = tabs.tab(for: source.boardID)
        let liveCardTitle = tab?.session.model?.item(id: source.itemID)?.title
        let cardTitle = liveCardTitle.flatMap { $0.isEmpty ? nil : $0 } ?? source.cardTitle
        let entry = nowPlaying
        return NowPlayingSummary(
            itemID: source.itemID,
            boardID: source.boardID,
            route: tab?.route ?? source.route,
            title: entry?.title ?? cardTitle,
            artist: entry?.subtitle ?? source.music.subtitle,
            boardTitle: tab?.title ?? source.boardTitle,
            cardTitle: cardTitle,
            phase: isLoading ? .loading : phase(of: source.itemID),
            canSkipBackward: canSkipBackward,
            duration: entry?.duration,
            shuffle: canShuffle ? shuffle : nil,
            repeatMode: canRepeat ? repeatMode : nil,
            canSeek: canSeek,
            artwork: entry?.artwork,
            fallbackMusic: source.music)
    }
}

/// O que cada controle faz.
struct NowPlayingActions {
    var openSource: () -> Void
    var playPause: () -> Void
    var previous: () -> Void
    var next: () -> Void
    var stop: () -> Void
    var toggleShuffle: () -> Void = {}
    var cycleRepeat: () -> Void = {}
    var seek: (TimeInterval) -> Void = { _ in }
}

#if DEBUG
extension NowPlayingSummary {
    /// Amostras para as prévias.
    static func sample(
        title: String = "Faixa 1", artist: String? = "Artista", phase: MusicCardPhase = .playing,
        kind: MusicItemKind = .album, duration: TimeInterval? = 180, boardTitle: String = "Inspirações",
        cardTitle: String = "Disco Inventado", shuffle: MusicShuffle? = .off, repeatMode: MusicRepeat? = MusicRepeat.none
    ) -> NowPlayingSummary {
        NowPlayingSummary(
            itemID: UUID(), boardID: BoardID(rawValue: UUID()), route: .library, title: title, artist: artist,
            boardTitle: boardTitle, cardTitle: cardTitle, phase: phase, canSkipBackward: kind != .station,
            duration: duration, shuffle: kind == .station ? nil : shuffle, repeatMode: repeatMode,
            canSeek: duration != nil, artwork: nil,
            fallbackMusic: MusicSnapshot(
                kind: kind, title: cardTitle, subtitle: artist, backgroundHex: "#2b5876", primaryTextHex: "#ffffff"))
    }

    static let playing = sample()
    static let paused = sample(phase: .paused)
    static let loading = sample(phase: .loading)
    static let station = sample(
        title: "Rádio do Artista", artist: nil, kind: .station, duration: nil, cardTitle: "Rádio do Artista")
    static let longTitles = sample(
        title: "Uma faixa com um título extraordinariamente longo para caber",
        artist: "Um artista com um nome igualmente comprido e cheio de colaboradores",
        boardTitle: "Um mural com um nome bem comprido", cardTitle: "Um álbum de título muito comprido também")
}
#endif
