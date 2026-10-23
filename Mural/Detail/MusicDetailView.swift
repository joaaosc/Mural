import MuralKit
import SwiftUI

/// Página mínima de um item do Apple Music: capa grande, título, artista, tipo e ano.
/// Mostra o último estado guardado; faixas e tocar vêm depois.
struct MusicDetailView: View {
    let item: BoardItem

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let music = item.music {
                    MusicArtwork(music: music, maxPixelSize: 960)
                        .frame(maxWidth: 320)
                        .clipShape(.rect(cornerRadius: Theme.cardCorner))
                        .cardShadow()
                        .padding(.bottom, 12)
                }
                Text(item.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                if let subtitle = item.music?.subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.title3).foregroundStyle(.secondary)
                }
                if let music = item.music {
                    Text([music.detailLine, music.releaseYear].compactMap { $0 }.joined(separator: " · "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.top, 100)
            .padding(.bottom, 110)
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity)
        }
        .background { (Color(muralHex: item.music?.backgroundHex)?.opacity(0.18) ?? .clear).ignoresSafeArea() }
        .discreetScrollIndicators()
    }
}

#Preview("Álbum") {
    MusicDetailView(
        item: BoardItem(
            kind: .music, title: "Abbey Road",
            music: MusicSnapshot(
                kind: .album, title: "Abbey Road", subtitle: "The Beatles", backgroundHex: "#1f3a5f", trackCount: 17,
                releaseDate: "1969-09-26")))
        .frame(width: 600, height: 700)
}
