import SwiftUI

/// A seção "Tocando agora" da barra lateral de murais, para quando o miniplayer mora ali: a capa, o título e o artista, e uma
/// fileira com anterior (fora das estações), tocar/pausar, próxima, o botão que devolve a música à cápsula flutuante e o que
/// a para.
///
/// Sem vidro nem material próprio: a barra lateral já tem fundo. Nada aqui toma o teclado, que é do mural aberto: o ⌘V precisa
/// continuar chegando a ele.
struct NowPlayingSidebarSection: View {
    let summary: NowPlayingSummary
    let actions: NowPlayingActions
    /// Chamado pelo botão que devolve a música à cápsula flutuante.
    let returnToMiniPlayer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sourceButton
            HStack(spacing: 0) {
                if summary.canSkipBackward {
                    control(
                        "Faixa anterior", symbol: "backward.fill", id: "sidebar-now-playing-previous",
                        action: actions.previous)
                }
                playPauseButton
                control("Próxima faixa", symbol: "forward.fill", id: "sidebar-now-playing-next", action: actions.next)
                Spacer(minLength: 0)
                control(
                    "Voltar ao miniplayer", symbol: "pip.enter", id: "sidebar-now-playing-return",
                    action: returnToMiniPlayer)
                control("Parar", symbol: "xmark", id: "sidebar-now-playing-stop", action: actions.stop)
            }
            .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .focusable(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tocando agora")
        .accessibilityIdentifier("sidebar-now-playing")
    }

    /// A capa, o título e o artista: um botão só, que abre o mural de origem (como "Abrir" no cartão expandido).
    private var sourceButton: some View {
        Button(action: actions.openSource) {
            HStack(spacing: 10) {
                NowPlayingArtwork(summary: summary, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(summary.title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    if let artist = summary.artist {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("Abrir o mural \(summary.boardTitle)")
        .accessibilityLabel(summary.artist.map { "\(summary.title), \($0)" } ?? summary.title)
        .accessibilityHint("Abre o mural de origem")
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
        .focusable(false)
        .disabled(isLoading)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier("sidebar-now-playing-play-pause")
    }

    private func control(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .frame(width: 30, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .focusable(false)
        .help(title)
        .accessibilityIdentifier(id)
    }
}

#if DEBUG
private struct SectionPreview: View {
    let summary: NowPlayingSummary

    var body: some View {
        NowPlayingSidebarSection(
            summary: summary,
            actions: NowPlayingActions(openSource: {}, playPause: {}, previous: {}, next: {}, stop: {}),
            returnToMiniPlayer: {}
        )
        .frame(width: MuralsSidebar.width)
        .background { SidebarFill() }
    }
}

#Preview("Tocando") { SectionPreview(summary: .playing) }

#Preview("Pausado, escuro") { SectionPreview(summary: .paused).preferredColorScheme(.dark) }

#Preview("Estação") { SectionPreview(summary: .station) }

#Preview("Títulos longos") { SectionPreview(summary: .longTitles) }

#Preview("Carregando, escuro") { SectionPreview(summary: .loading).preferredColorScheme(.dark) }
#endif
