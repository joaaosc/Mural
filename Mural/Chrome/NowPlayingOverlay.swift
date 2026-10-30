import SwiftUI

/// Liga o tocador e as abas ao miniplayer, por cima do conteúdo da janela.
///
/// As áreas vazias não recebem cliques: só a própria barra responde. Com o miniplayer levado para a barra lateral de murais
/// e ela à vista, a cápsula sai (os controles ficam lá); fechando a barra lateral, a cápsula volta, e a música nunca fica
/// sem controle à vista.
struct NowPlayingOverlay: View {
    let tabs: MuralTabs
    var playback: MusicPlayback = .shared
    /// Os controles do rodapé que a barra evita, em coordenadas desta view.
    let obstacles: [CGRect]
    let container: CGSize

    var dockStore: NowPlayingDockStore = .shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let summary = playback.summary(in: tabs)
        let floating = dockStore.isInSidebar && tabs.isSidebarVisible ? nil : summary
        ZStack(alignment: .bottomLeading) {
            if let floating {
                NowPlayingPositioned(
                    summary: floating, elapsed: { playback.playbackTime }, actions: actions(for: floating),
                    obstacles: obstacles, container: container, dock: dockStore.dock,
                    setDock: { dockStore.dock = $0 }
                )
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: floating?.itemID)
    }

    private func actions(for summary: NowPlayingSummary) -> NowPlayingActions {
        playback.nowPlayingActions(
            openSource: { tabs.showBoard(summary.route, title: summary.boardTitle) },
            moveToSidebar: {
                dockStore.isInSidebar = true
                tabs.isSidebarVisible = true
            })
    }
}
