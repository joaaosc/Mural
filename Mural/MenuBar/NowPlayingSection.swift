import SwiftUI

/// A seção "Tocando agora" do painel da barra de menus: a capa, de onde vem a música, a barra de tempo e os controles.
///
/// Sem vidro nem material próprio: o painel já os tem. Nada aqui toma o foco, que é do contêiner da vitrine (as setas
/// são do coverflow).
struct NowPlayingSection: View {
    let summary: NowPlayingSummary
    let elapsed: () -> TimeInterval
    let actions: NowPlayingActions

    /// Se a barra de tempo aparece: precisa de duração conhecida (estações não têm).
    static func showsScrubber(for summary: NowPlayingSummary) -> Bool {
        summary.canSeek && (summary.duration ?? 0) > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tocando agora")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 12) {
                NowPlayingArtwork(summary: summary, size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(summary.title)
                        .font(.headline)
                        .lineLimit(1)
                    if let artist = summary.artist {
                        Text(artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        Text(summary.sourceLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .accessibilityIdentifier("menu-bar-now-playing-source")
                        Button("Abrir", action: actions.openSource)
                            .controlSize(.small)
                            .buttonStyle(.borderless)
                            .focusable(false)
                            .help("Abrir o mural \(summary.boardTitle)")
                            .accessibilityIdentifier("menu-bar-now-playing-open")
                    }
                }
                Spacer(minLength: 0)
            }
            if Self.showsScrubber(for: summary), let duration = summary.duration {
                NowPlayingScrubber(
                    duration: duration, isPlaying: summary.phase == .playing, elapsed: elapsed, seek: actions.seek,
                    id: "menu-bar-now-playing-scrubber"
                )
                .focusable(false)
            }
            NowPlayingControls(
                summary: summary, actions: actions,
                ids: .init(
                    shuffle: "menu-bar-now-playing-shuffle", previous: "menu-bar-now-playing-previous",
                    playPause: "menu-bar-now-playing-play-pause", next: "menu-bar-now-playing-next",
                    repeatMode: "menu-bar-now-playing-repeat", stop: "menu-bar-now-playing-stop"),
                buttonWidth: 36, showsStop: true, takesFocus: false
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, PanelMetrics.contentPadding)
        .padding(.bottom, PanelMetrics.contentSpacing)
        .focusable(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tocando agora")
        .accessibilityIdentifier("menu-bar-now-playing")
    }
}

#if DEBUG
private let previewSectionActions = NowPlayingActions(openSource: {}, playPause: {}, previous: {}, next: {}, stop: {})

private struct SectionPreview: View {
    let summary: NowPlayingSummary

    var body: some View {
        NowPlayingSection(summary: summary, elapsed: { 75 }, actions: previewSectionActions)
            .padding(.top, PanelMetrics.contentPadding)
            .frame(width: 600)
            .background(.regularMaterial)
    }
}

#Preview("Tocando") { SectionPreview(summary: .playing) }

#Preview("Pausado") { SectionPreview(summary: .paused).preferredColorScheme(.dark) }

#Preview("Estação") { SectionPreview(summary: .station) }

#Preview("Títulos longos") { SectionPreview(summary: .longTitles) }

#Preview("Carregando") { SectionPreview(summary: .loading) }
#endif
