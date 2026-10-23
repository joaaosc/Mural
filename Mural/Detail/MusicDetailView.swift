import MuralKit
import SwiftUI

/// Página de um item do Apple Music: capa grande, título, artista, botões de tocar e, em álbum ou playlist, as faixas.
struct MusicDetailView: View {
    let item: BoardItem
    let session: BoardWindowSession?

    @Environment(\.musicArtworkCoordinator) private var artwork
    @State private var trackList = MusicTrackList()

    var body: some View {
        // O item vem de fora e muda quando o tocador resolve o cartão; a página relê sempre.
        MusicDetailContent(
            item: item,
            state: trackList.state,
            phase: session?.musicPhase(of: item.id) ?? .idle,
            canPlay: session != nil,
            onToggle: { Task { await session?.toggleMusic(item.id) } },
            onOpenInMusic: { session?.openMusicInApp(item.id) },
            onPlayTrack: { id in Task { await session?.playMusic(item.id, startingAt: id) } },
            onAllowAccess: {
                guard let session, let music = item.music else { return }
                Task { await trackList.allowAccess(music, playback: session.musicPlayback) }
            }
        )
        .task(id: item.id) {
            guard let session, let music = item.music else { return }
            await trackList.load(music, playback: session.musicPlayback)
            await session.completeMusicArtwork(item.id, artwork: artwork)
        }
    }
}

/// Desenho da página com o estado injetado, para as prévias.
struct MusicDetailContent: View {
    let item: BoardItem
    let state: MusicTrackList.State
    let phase: MusicCardPhase
    let canPlay: Bool
    var onToggle: () -> Void = {}
    var onOpenInMusic: () -> Void = {}
    var onPlayTrack: (String) -> Void = { _ in }
    var onAllowAccess: () -> Void = {}

    @State private var isNarrow = false

    private static let artworkSide: CGFloat = 240

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header
                tracks
            }
            .frame(maxWidth: .infinity, alignment: isNarrow ? .center : .leading)
            .padding(.top, 100)
            .padding(.bottom, 110)
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: Bool.self) {
            $0.size.width < 640
        } action: {
            isNarrow = $0
        }
        .background { (Color(muralHex: item.music?.backgroundHex)?.opacity(0.18) ?? .clear).ignoresSafeArea() }
        .discreetScrollIndicators()
    }

    // MARK: Cabeçalho

    @ViewBuilder
    private var header: some View {
        if isNarrow {
            VStack(alignment: .center, spacing: 20) {
                artworkView
                info(alignment: .center)
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(alignment: .bottom, spacing: 28) {
                artworkView
                info(alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var artworkView: some View {
        if let music = item.music {
            MusicArtwork(music: music, maxPixelSize: 960)
                .frame(width: Self.artworkSide, height: Self.artworkSide)
                .clipShape(.rect(cornerRadius: Theme.cardCorner))
                .cardShadow()
        }
    }

    private func info(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 8) {
            if let music = item.music {
                Text([music.detailLine, music.releaseYear].compactMap { $0 }.joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text(item.title)
                .font(.system(size: 34, weight: .bold))
                .textSelection(.enabled)
            if let subtitle = item.music?.subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.title3).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if canPlay { buttons.padding(.top, 8) }
        }
        .multilineTextAlignment(alignment == .center ? .center : .leading)
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    if phase == .loading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: phase == .playing ? "pause.fill" : "play.fill")
                    }
                    Text(phase == .playing ? "Pausar" : "Tocar")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Abrir no Música", action: onOpenInMusic)
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }

    // MARK: Faixas

    @ViewBuilder
    private var tracks: some View {
        switch state {
        case .idle, .hidden:
            EmptyView()
        case .loading:
            ProgressView().frame(maxWidth: 640)
        case .loaded(let rows):
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    if row.id != rows.first?.id { Divider() }
                    MusicTrackRowView(row: row, itemSubtitle: item.music?.subtitle, canPlay: canPlay) { onPlayTrack(row.id) }
                }
            }
            .frame(maxWidth: 640)
        case .needsAccess:
            VStack(alignment: .leading, spacing: 12) {
                Text("Para ver as faixas, o Mural precisa do acesso ao Apple Music.").foregroundStyle(.secondary)
                Button("Permitir acesso", action: onAllowAccess)
            }
            .frame(maxWidth: 640, alignment: .leading)
        case .denied:
            Text("O acesso ao Apple Music está desligado em Ajustes do Sistema › Privacidade e Segurança › Mídia e Apple Music.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: 640, alignment: .leading)
        case .unavailable:
            Text("As faixas não puderam ser carregadas.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: 640, alignment: .leading)
        }
    }
}

/// Uma faixa da lista: toca a partir dela ao clicar.
private struct MusicTrackRowView: View {
    let row: MusicTrackRow
    let itemSubtitle: String?
    let canPlay: Bool
    let onPlay: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                Text("\(row.number)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
                Text(row.title).lineLimit(1)
                if let artist = row.artist, !artist.isEmpty, artist != itemSubtitle {
                    Text(artist).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if let duration = row.duration {
                    Text(MusicSnapshot.clock(duration)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering && canPlay ? Color.primary.opacity(0.07) : .clear, in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!canPlay)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Tocar \(row.title)")
    }
}

#Preview("Álbum, claro") {
    MusicDetailContent(item: MusicPreviewData.item, state: .loaded(MusicPreviewData.rows), phase: .idle, canPlay: true)
        .frame(width: 900, height: 700)
        .preferredColorScheme(.light)
}

#Preview("Álbum, escuro, tocando") {
    MusicDetailContent(item: MusicPreviewData.item, state: .loaded(MusicPreviewData.rows), phase: .playing, canPlay: true)
        .frame(width: 900, height: 700)
        .preferredColorScheme(.dark)
}

#Preview("Janela estreita") {
    MusicDetailContent(item: MusicPreviewData.item, state: .needsAccess, phase: .idle, canPlay: true)
        .frame(width: 520, height: 700)
}

private enum MusicPreviewData {
    static let item = BoardItem(
        kind: .music, title: "Abbey Road",
        music: MusicSnapshot(
            kind: .album, title: "Abbey Road", subtitle: "The Beatles", backgroundHex: "#1f3a5f", trackCount: 17,
            releaseDate: "1969-09-26"))
    static let rows = [
        MusicTrackRow(id: "1", number: 1, title: "Come Together", artist: "The Beatles", duration: 259),
        MusicTrackRow(id: "2", number: 2, title: "Something", artist: "The Beatles", duration: 183),
        MusicTrackRow(id: "3", number: 3, title: "Here Comes the Sun", artist: "George Harrison", duration: 185),
    ]
}
