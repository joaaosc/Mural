import MuralKit
import MusicKit
import SwiftUI

/// A capa de quem toca: a do tocador (pelo MusicKit) ou, sem ela, a do cartão.
struct NowPlayingArtwork: View {
    let summary: NowPlayingSummary
    let size: CGFloat

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
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}

/// Miniplayer: uma cápsula de vidro com a capa, o título e os controles. Mostra menos coisas quando falta largura.
///
/// Vidro estático por trás de botões sem borda, como o `ActionPill`. Nunca `.interactive()`: ver o aviso em
/// `FloatingToolbar`.
struct NowPlayingBar: View {
    let summary: NowPlayingSummary
    /// Posição na entrada atual, lida a cada passo da linha de progresso.
    let elapsed: () -> TimeInterval
    let actions: NowPlayingActions

    private enum Form {
        case full, medium, compact
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            content(.full)
            content(.medium)
            content(.compact)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) { progress }
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tocando agora")
        .accessibilityIdentifier("now-playing-bar")
    }

    private func content(_ form: Form) -> some View {
        HStack(spacing: 2) {
            sourceButton(showsText: form != .compact, textWidth: form == .full ? 200 : 110)
            if form != .compact {
                transport(
                    "Faixa anterior", symbol: "backward.fill", id: "now-playing-previous",
                    isEnabled: summary.canSkipBackward, action: actions.previous)
            }
            playPauseButton
            transport("Próxima faixa", symbol: "forward.fill", id: "now-playing-next", action: actions.next)
            if form != .compact {
                transport("Parar", symbol: "xmark", id: "now-playing-stop", action: actions.stop)
            }
        }
        .font(.body.weight(.medium))
    }

    private func sourceButton(showsText: Bool, textWidth: CGFloat) -> some View {
        Button(action: actions.openSource) {
            HStack(spacing: 8) {
                NowPlayingArtwork(summary: summary, size: 32)
                if showsText {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(summary.title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        if let artist = summary.artist {
                            Text(artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: textWidth, alignment: .leading)
                }
            }
            .padding(.leading, 2)
            .padding(.trailing, showsText ? 8 : 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Abrir o mural \(summary.boardTitle)")
        .accessibilityLabel(summary.artist.map { "\(summary.title), \($0)" } ?? summary.title)
        .accessibilityHint("Abre o mural \(summary.boardTitle)")
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
            .frame(width: 34, height: 30)
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
                .frame(width: 34, height: 30)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .help(title)
        .accessibilityIdentifier(id)
    }

    /// Linha de 2 pt com o quanto da entrada já tocou; só quando a duração é conhecida.
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
                    .frame(height: 2)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 2)
            .accessibilityHidden(true)
        }
    }
}

/// O miniplayer no canto inferior esquerdo, com a largura e a altura que sobram ao lado dos controles do rodapé.
struct NowPlayingPositioned: View {
    let summary: NowPlayingSummary
    let elapsed: () -> TimeInterval
    let actions: NowPlayingActions
    let obstacles: [CGRect]
    let container: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let placement = NowPlayingPlacement(container: container, obstacles: obstacles)
        NowPlayingBar(summary: summary, elapsed: elapsed, actions: actions)
            .frame(maxWidth: placement.maxWidth)
            .padding(.leading, NowPlayingPlacement.margin)
            .padding(.bottom, placement.bottomPadding)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: placement)
    }
}

#if DEBUG
private let previewActions = NowPlayingActions(
    openSource: {}, playPause: {}, previous: {}, next: {}, stop: {})

private struct PreviewBar: View {
    let summary: NowPlayingSummary
    var width: CGFloat?

    var body: some View {
        NowPlayingBar(summary: summary, elapsed: { 60 }, actions: previewActions)
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            .frame(width: size.width, height: size.height)
    }
}

#Preview("Tocando") { PreviewBar(summary: .playing) }

#Preview("Pausado") {
    PreviewBar(summary: .paused).preferredColorScheme(.dark)
}

#Preview("Título longo") { PreviewBar(summary: .longTitles, width: 300) }

#Preview("Compacta") { PreviewBar(summary: .playing, width: 130) }

#Preview("Estação") { PreviewBar(summary: .station) }

#Preview("Carregando") { PreviewBar(summary: .loading) }

#Preview("Lugar na janela 1000") { PreviewPlacement(size: CGSize(width: 1000, height: 400)) }

#Preview("Lugar na janela 520") { PreviewPlacement(size: CGSize(width: 520, height: 400)) }
#endif
