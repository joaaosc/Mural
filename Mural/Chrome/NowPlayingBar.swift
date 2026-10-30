import MuralKit
import MusicKit
import SwiftUI

/// A capa de quem toca: a do tocador (pelo MusicKit) ou, sem ela, a do cartão.
struct NowPlayingArtwork: View {
    let summary: NowPlayingSummary
    let size: CGFloat
    var cornerRadius: CGFloat = 6

    var body: some View {
        Group {
            if let artwork = summary.artwork {
                ArtworkImage(artwork, width: size, height: size)
            } else {
                MusicArtwork(music: summary.fallbackMusic, maxPixelSize: Int(size * 3))
                    .environment(
                        \.linkPreviewFiles,
                        LinkPreviewFiles(directory: LaunchConfiguration.linkPreviewsDirectory(for: summary.boardID)))
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
    }
}

/// Miniplayer compacto: uma cápsula discreta de vidro com a capa, o título, tocar/pausar e próxima. Clicar na capa ou no
/// título expande o cartão (ver `NowPlayingExpanded`).
///
/// Vidro estático por trás de botões sem borda, como o `ActionPill`. Nunca `.interactive()`: ver o aviso em
/// `FloatingToolbar`.
struct NowPlayingBar: View {
    /// Altura da cápsula.
    static let height: CGFloat = 40

    let summary: NowPlayingSummary
    /// Posição na entrada atual, lida a cada passo da linha de progresso.
    let elapsed: () -> TimeInterval
    let actions: NowPlayingActions
    /// Chamado ao clicar na capa ou no título.
    let expand: () -> Void
    let glassNamespace: Namespace.ID

    var body: some View {
        HStack(spacing: 0) {
            sourceButton
            playPauseButton
            transport("Próxima faixa", symbol: "forward.fill", id: "now-playing-next", action: actions.next)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 6)
        .frame(height: Self.height)
        .overlay(alignment: .bottom) { progress }
        .glassEffect(.regular, in: .capsule)
        .glassEffectID("pill", in: glassNamespace)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tocando agora")
        .accessibilityIdentifier("now-playing-bar")
    }

    private var sourceButton: some View {
        Button(action: expand) {
            HStack(spacing: 8) {
                NowPlayingArtwork(summary: summary, size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(summary.title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    if let artist = summary.artist {
                        Text(artist)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Expandir o player")
        .accessibilityLabel(summary.artist.map { "\(summary.title), \($0)" } ?? summary.title)
        .accessibilityHint("Expande o player")
        .accessibilityIdentifier("now-playing-source")
    }

    private var playPauseButton: some View {
        let isLoading = summary.phase == .loading
        let title = isLoading ? "Carregando" : (summary.phase == .playing ? "Pausar" : "Tocar")
        return Button(action: actions.playPause) {
            Group {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Label(title, systemImage: summary.phase == .playing ? "pause.fill" : "play.fill")
                        .labelStyle(.iconOnly)
                }
            }
            .frame(width: 30, height: 28)
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .disabled(isLoading)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier("now-playing-play-pause")
    }

    private func transport(
        _ title: String, symbol: String, id: String, isEnabled: Bool = true, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .frame(width: 30, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .help(title)
        .accessibilityIdentifier(id)
    }

    /// Linha fina com o quanto da entrada já tocou; só quando a duração é conhecida.
    @ViewBuilder
    private var progress: some View {
        if let duration = summary.duration, duration > 0 {
            TimelineView(.animation(minimumInterval: 1, paused: summary.phase != .playing)) { _ in
                let fraction = min(max(elapsed() / duration, 0), 1)
                Capsule()
                    .fill(.quaternary)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.secondary)
                            .scaleEffect(x: fraction, anchor: .leading)
                    }
                    .frame(height: 1.5)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 2)
            .accessibilityHidden(true)
        }
    }
}

/// O miniplayer centralizado no rodapé da janela, acima dos controles do rodapé que cruzem o lugar dele. Clicar na
/// cápsula abre o cartão expandido acima.
struct NowPlayingPositioned: View {
    let summary: NowPlayingSummary
    let elapsed: () -> TimeInterval
    let actions: NowPlayingActions
    let obstacles: [CGRect]
    let container: CGSize

    /// O vão entre o cartão expandido e a cápsula, em pontos.
    private static let cardGap: CGFloat = 10

    @Namespace private var glassNamespace
    @State private var isExpanded = false
    @FocusState private var cardHasFocus: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let placement = NowPlayingPlacement(container: container, obstacles: obstacles)
        // `spacing: 0`: o vidro só se funde com formas que se tocam; com o vão de `cardGap`, o cartão e a cápsula ficam
        // duas formas separadas, sem "cola" entre elas.
        GlassEffectContainer(spacing: 0) {
            VStack(spacing: Self.cardGap) {
                if isExpanded {
                    NowPlayingExpanded(
                        summary: summary, elapsed: elapsed, actions: expandedActions, glassNamespace: glassNamespace,
                        reducesMotion: reduceMotion
                    )
                    .focusable()
                    .focused($cardHasFocus)
                    .focusEffectDisabled()
                    .onAppear { cardHasFocus = true }
                    .onExitCommand { setExpanded(false) }
                    .transition(reduceMotion ? .opacity : .identity)
                }
                NowPlayingBar(
                    summary: summary, elapsed: elapsed, actions: actions, expand: { setExpanded(!isExpanded) },
                    glassNamespace: glassNamespace
                )
                .frame(width: placement.maxWidth)
            }
        }
        .padding(.horizontal, NowPlayingPlacement.margin)
        .padding(.bottom, placement.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background {
            // Um clique fora do cartão o recolhe.
            if isExpanded {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { setExpanded(false) }
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: placement.bottomPadding)
    }

    // MARK: Expandir

    /// O cartão com "Abrir" recolhendo-o depois de abrir o mural.
    private var expandedActions: NowPlayingActions {
        var expanded = actions
        expanded.openSource = {
            actions.openSource()
            setExpanded(false)
        }
        return expanded
    }

    private func setExpanded(_ value: Bool) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.4, bounce: 0.15)) {
            isExpanded = value
        }
    }
}

#if DEBUG
private let previewActions = NowPlayingActions(
    openSource: {}, playPause: {}, previous: {}, next: {}, stop: {})

private struct PreviewBar: View {
    let summary: NowPlayingSummary
    var width: CGFloat? = 260
    @Namespace private var namespace

    var body: some View {
        NowPlayingBar(summary: summary, elapsed: { 60 }, actions: previewActions, expand: {}, glassNamespace: namespace)
            .frame(maxWidth: width)
            .padding(40)
            .background(Theme.canvas)
    }
}

/// Simula a janela: uma barra de criação ao centro e o zoom à direita, ambos marcados como obstáculos.
private struct PreviewPlacement: View {
    let size: CGSize

    var body: some View {
        Theme.canvas
            .overlay(alignment: .bottom) {
                Capsule().fill(.regularMaterial).frame(width: 280, height: 48)
                    .nowPlayingObstacle()
                    .padding(.bottom, 18)
            }
            .overlay(alignment: .bottomTrailing) {
                Capsule().fill(.regularMaterial).frame(width: 60, height: 40)
                    .nowPlayingObstacle()
                    .padding(18)
            }
            .overlayPreferenceValue(NowPlayingObstacleKey.self) { anchors in
                GeometryReader { proxy in
                    NowPlayingPositioned(
                        summary: .playing, elapsed: { 60 }, actions: previewActions,
                        obstacles: anchors.map { proxy[$0] }, container: proxy.size
                    )
                }
            }
            .frame(width: size.width, height: size.height)
    }
}

#Preview("Tocando") { PreviewBar(summary: .playing) }

#Preview("Pausado") {
    PreviewBar(summary: .paused).preferredColorScheme(.dark)
}

#Preview("Título longo") { PreviewBar(summary: .longTitles) }

#Preview("Estação") { PreviewBar(summary: .station) }

#Preview("Carregando") { PreviewBar(summary: .loading) }

#Preview("Lugar na janela 1000") { PreviewPlacement(size: CGSize(width: 1000, height: 400)) }

#Preview("Lugar na janela 520") { PreviewPlacement(size: CGSize(width: 520, height: 400)) }
#endif
