import MuralKit
import SwiftUI

extension MusicSnapshot {
    /// A cor da capa, quando veio; `nil` deixa o papel com quem desenha.
    var paperColor: Color? { Color(muralHex: backgroundHex) }

    /// O texto principal sobre a cor da capa.
    var primaryTextColor: Color {
        Color(muralHex: primaryTextHex) ?? Color.readable(onHex: backgroundHex) ?? .primary
    }

    /// O texto secundário sobre a cor da capa.
    var secondaryTextColor: Color {
        Color(muralHex: secondaryTextHex) ?? Color.readable(onHex: backgroundHex)?.opacity(0.7) ?? .secondary
    }
}

/// O desenho de um cartão de música a partir do estado guardado: a capa quadrada no topo e, abaixo, o tipo, o título e o
/// artista.
///
/// Serve ao cartão solto (`MusicCard`) e à música embutida numa nota (`EmbeddedCardView`); o pedido da capa fica com quem o
/// usa. As fontes são fixas de propósito, como nas notas e nos links.
struct MusicCardContent: View {
    let music: MusicSnapshot
    let title: String
    /// Maior lado, em pixels, da capa; sobe quando o cartão é ampliado, para a capa não ficar borrada.
    var artworkMaxPixelSize = 480

    private var primary: Color { music.primaryTextColor }
    private var secondary: Color { music.secondaryTextColor }
    private var paper: Color { music.paperColor ?? Theme.paper }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // A capa ocupa a largura toda e o que sobra acima do texto: no mural, quase um quadrado.
            MusicArtwork(music: music, maxPixelSize: artworkMaxPixelSize).frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 4) {
                kindRow
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(primary)
                    .lineLimit(2)
                if let subtitle = music.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 7.5))
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
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

    private var kindRow: some View {
        HStack(spacing: 3) {
            Image(systemName: music.kind.symbol)
                .font(.system(size: 6.5))
            Text(music.detailLine)
                .font(.system(size: 6.5, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(secondary)
    }

    private var accessibilityText: String {
        var parts = [music.kind.displayName, title]
        if let subtitle = music.subtitle, !subtitle.isEmpty { parts.append(subtitle) }
        return parts.joined(separator: ", ")
    }
}
