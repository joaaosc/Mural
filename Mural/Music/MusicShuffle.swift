/// Aleatório do tocador. O valor `nil` do tocador (estações, por exemplo) é "indisponível".
enum MusicShuffle: Equatable, Sendable {
    case off
    case songs

    /// O outro estado, para o botão que liga e desliga.
    var toggled: MusicShuffle { self == .off ? .songs : .off }
}
