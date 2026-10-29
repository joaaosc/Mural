import SwiftUI

/// A seção "Tocando agora" do painel da barra de menus: a capa, de onde vem a música e os controles.
///
/// Sem vidro nem material próprio: o painel já os tem. Os botões não tomam o foco, que é do contêiner da vitrine.
struct NowPlayingSection: View {
    let summary: NowPlayingSummary
    let actions: NowPlayingActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tocando agora")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 12) {
                NowPlayingArtwork(summary: summary, size: 44)
                VStack(alignment: .leading, spacing: 2) {
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
                Spacer(minLength: 8)
                transportButtons
            }
        }
        .padding(.horizontal, PanelMetrics.contentPadding)
        .padding(.bottom, PanelMetrics.contentSpacing)
        .focusable(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tocando agora")
        .accessibilityIdentifier("menu-bar-now-playing")
    }

    private var transportButtons: some View {
        let isLoading = summary.phase == .loading
        let playPauseTitle = isLoading ? "Carregando" : (summary.phase == .playing ? "Pausar" : "Tocar")
        return HStack(spacing: 2) {
            button(
                "Faixa anterior", symbol: "backward.fill", id: "menu-bar-now-playing-previous",
                isEnabled: summary.canSkipBackward, action: actions.previous)
            Button(action: actions.playPause) {
                Group {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(playPauseTitle, systemImage: summary.phase == .playing ? "pause.fill" : "play.fill")
                            .labelStyle(.iconOnly)
                    }
                }
                .frame(width: 34, height: 30)
                .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .focusable(false)
            .disabled(isLoading)
            .help(playPauseTitle)
            .accessibilityLabel(playPauseTitle)
            .accessibilityIdentifier("menu-bar-now-playing-play-pause")
            button("Próxima faixa", symbol: "forward.fill", id: "menu-bar-now-playing-next", action: actions.next)
            button("Parar", symbol: "xmark", id: "menu-bar-now-playing-stop", action: actions.stop)
        }
        .font(.body.weight(.medium))
    }

    private func button(
        _ title: String, symbol: String, id: String, isEnabled: Bool = true, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .frame(width: 34, height: 30)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .focusable(false)
        .disabled(!isEnabled)
        .help(title)
        .accessibilityIdentifier(id)
    }
}

#if DEBUG
private let previewSectionActions = NowPlayingActions(openSource: {}, playPause: {}, previous: {}, next: {}, stop: {})

private struct SectionPreview: View {
    let summary: NowPlayingSummary

    var body: some View {
        NowPlayingSection(summary: summary, actions: previewSectionActions)
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
