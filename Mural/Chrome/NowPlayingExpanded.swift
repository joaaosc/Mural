import SwiftUI

/// O cartão expandido do miniplayer: capa grande, título, artista, origem com "Abrir", barra de tempo e controles.
///
/// Surge de cima da cápsula compacta (mesmo `GlassEffectContainer`, com espaçamento 0 e um vão: as duas formas de vidro
/// não se fundem). Vidro estático, nunca `.interactive()`: ver o aviso em `FloatingToolbar`.
struct NowPlayingExpanded: View {
    static let width: CGFloat = 320

    let summary: NowPlayingSummary
    let elapsed: () -> TimeInterval
    let actions: NowPlayingActions
    let glassNamespace: Namespace.ID
    /// Reduzir Movimento: sem a transformação do vidro, só aparece e some.
    let reducesMotion: Bool

    var body: some View {
        VStack(spacing: 12) {
            NowPlayingArtwork(summary: summary, size: 180, cornerRadius: 12)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            VStack(spacing: 2) {
                Text(summary.title)
                    .font(.headline)
                    .lineLimit(1)
                if let artist = summary.artist {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(.center)
            sourceLine
            if let duration = summary.duration, duration > 0, summary.canSeek {
                NowPlayingScrubber(
                    duration: duration, isPlaying: summary.phase == .playing, elapsed: elapsed, seek: actions.seek,
                    id: "now-playing-scrubber")
            }
            NowPlayingControls(
                summary: summary, actions: actions,
                ids: .init(
                    shuffle: "now-playing-shuffle", previous: "now-playing-previous",
                    playPause: "now-playing-expanded-play-pause", next: "now-playing-expanded-next",
                    repeatMode: "now-playing-repeat", stop: "now-playing-stop"))
        }
        .padding(16)
        .frame(width: Self.width)
        .overlay(alignment: .topTrailing) {
            Button(action: actions.stop) {
                Label("Parar", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.caption.weight(.bold))
                    .frame(width: 24, height: 24)
                    .contentShape(.circle)
            }
            .buttonStyle(.borderless)
            .padding(8)
            .help("Parar")
            .accessibilityIdentifier("now-playing-stop")
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .glassEffectID("card", in: glassNamespace)
        .glassEffectTransition(reducesMotion ? .identity : .matchedGeometry)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tocando agora, expandido")
        .accessibilityIdentifier("now-playing-expanded")
    }

    private var sourceLine: some View {
        HStack(spacing: 8) {
            Text(summary.sourceLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Button("Abrir", action: actions.openSource)
                .controlSize(.small)
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
                .help("Abrir o mural \(summary.boardTitle)")
                .accessibilityIdentifier("now-playing-open")
        }
    }
}

#if DEBUG
private struct ExpandedPreview: View {
    let summary: NowPlayingSummary
    @Namespace private var namespace

    var body: some View {
        GlassEffectContainer {
            NowPlayingExpanded(
                summary: summary, elapsed: { 75 },
                actions: NowPlayingActions(
                    openSource: {}, playPause: {}, previous: {}, next: {}, stop: {}),
                glassNamespace: namespace, reducesMotion: false)
        }
        .padding(40)
        .background(Theme.canvas)
    }
}

#Preview("Expandido") { ExpandedPreview(summary: .playing) }

#Preview("Estação") { ExpandedPreview(summary: .station) }

#Preview("Títulos longos") { ExpandedPreview(summary: .longTitles).preferredColorScheme(.dark) }
#endif
