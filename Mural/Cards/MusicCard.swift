import MuralKit
import SwiftUI

/// Capa de um item do Apple Music: o arquivo guardado, se está na pasta de prévias; sem ele, um quadrado
/// na cor da capa (ou num papel um pouco mais escuro) com o símbolo do tipo no centro.
struct MusicArtwork: View {
    let music: MusicSnapshot
    var maxPixelSize = 480

    @Environment(\.linkPreviewFiles) private var files

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { content }
            .clipped()
    }

    @ViewBuilder
    private var content: some View {
        if let name = music.artworkFile, let url = files?.existingURL(for: name) {
            ThumbnailView(url: url, kind: .image, maxPixelSize: maxPixelSize)
        } else {
            (Color(muralHex: music.backgroundHex) ?? Theme.paper.mix(with: .black, by: 0.08))
                .overlay {
                    Image(systemName: music.kind.symbol)
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(Color(muralHex: music.primaryTextHex) ?? .secondary)
                        .accessibilityHidden(true)
                }
        }
    }
}

/// Cartão de música em miniatura: a capa quadrada no topo e, abaixo, o tipo, o título e o artista.
///
/// Desenhado só pelo estado guardado no cartão. As fontes são fixas de propósito, como nas notas e nos links.
struct MusicCard: View {
    let item: BoardItem

    private var music: MusicSnapshot? { item.music }
    private var primary: Color { Color(muralHex: music?.primaryTextHex) ?? .primary }
    private var secondary: Color { Color(muralHex: music?.secondaryTextHex) ?? Color.secondary }
    private var paper: Color { Color(muralHex: music?.backgroundHex) ?? Theme.paper }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let music { MusicArtwork(music: music) }
            VStack(alignment: .leading, spacing: 4) {
                kindRow
                Text(item.title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(primary)
                    .lineLimit(2)
                if let subtitle = music?.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 7.5))
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(.rect(cornerRadius: Theme.cardCorner))
        // A sombra é só do papel, como no cartão de link.
        .background {
            RoundedRectangle(cornerRadius: Theme.cardCorner)
                .fill(paper)
                .cardShadow()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var kindRow: some View {
        if let music {
            HStack(spacing: 3) {
                Image(systemName: music.kind.symbol)
                    .font(.system(size: 6.5))
                Text(music.detailLine)
                    .font(.system(size: 6.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(secondary)
        }
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let music { parts.append(music.kind.displayName) }
        parts.append(item.title)
        if let subtitle = music?.subtitle, !subtitle.isEmpty { parts.append(subtitle) }
        return parts.joined(separator: ", ")
    }
}

/// Álbum com cores, faixa sem capa e playlist só com nome, no claro e no escuro.
private struct MusicCardSamples: View {
    var body: some View {
        HStack(spacing: 16) {
            sample(
                MusicSnapshot(
                    kind: .album, title: "Abbey Road", subtitle: "The Beatles", backgroundHex: "#1f3a5f",
                    primaryTextHex: "#ffffff", secondaryTextHex: "#c9d6e8", trackCount: 17))
            sample(MusicSnapshot(kind: .song, title: "Something", subtitle: "The Beatles", duration: 183))
            sample(MusicSnapshot(kind: .playlist, title: "Para ouvir de manhã"))
        }
    }

    private func sample(_ music: MusicSnapshot) -> some View {
        MusicCard(item: BoardItem(kind: .music, title: music.title, music: music))
            .frame(width: 150, height: 196)
    }
}

#Preview("Claro", traits: .fixedLayout(width: 540, height: 240)) {
    MusicCardSamples().padding(20).background(Theme.canvas)
}

#Preview("Escuro", traits: .fixedLayout(width: 540, height: 240)) {
    MusicCardSamples().padding(20).background(Theme.canvas).preferredColorScheme(.dark)
}
