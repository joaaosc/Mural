import SwiftUI

/// Liga o tocador e as abas ao miniplayer, por cima do conteúdo da janela.
///
/// As áreas vazias não recebem cliques: só a própria barra responde.
struct NowPlayingOverlay: View {
    let tabs: MuralTabs
    var playback: MusicPlayback = .shared
    /// Os controles do rodapé que a barra evita, em coordenadas desta view.
    let obstacles: [CGRect]
    let container: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let summary = playback.summary(in: tabs)
        ZStack(alignment: .bottomLeading) {
            if let summary {
                NowPlayingPositioned(
                    summary: summary, elapsed: { playback.playbackTime }, actions: actions(for: summary),
                    obstacles: obstacles, container: container
                )
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: summary?.itemID)
    }

    private func actions(for summary: NowPlayingSummary) -> NowPlayingActions {
        NowPlayingActions(
            openSource: { tabs.showBoard(summary.route, title: summary.boardTitle) },
            playPause: { Task { await playback.pauseOrResume() } },
            previous: { Task { await playback.skipToPrevious() } },
            next: { Task { await playback.skipToNext() } },
            stop: { playback.stopCurrent() },
            toggleShuffle: { playback.toggleShuffle() },
            cycleRepeat: { playback.cycleRepeat() },
            seek: { playback.seek(to: $0) })
    }
}
