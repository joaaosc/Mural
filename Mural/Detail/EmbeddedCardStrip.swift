import MuralKit
import SwiftUI

/// O cartão embutido numa nota, em forma de tira: mais largo que alto, com a miniatura à esquerda e o título e o detalhe ao lado.
///
/// Dentro do texto o desenho do cartão solto ocupava quase uma página (uma música chegava a 448 pt de altura); a tira deixa o
/// texto em primeiro plano. Serve à página de leitura e ao editor de texto, que a desenha como imagem: sem arquivo guardado, nada
/// aqui depende de carregamento assíncrono.
struct EmbeddedCardStrip: View {
    let card: EmbeddedCard
    let title: String
    /// O estado do tocador, quando o cartão é uma música embutida; mostra o selo de tocando ou pausado.
    var phase: MusicCardPhase = .idle

    /// Largura máxima da tira, em pontos.
    nonisolated static let maximumWidth: CGFloat = 320
    /// Altura da tira, em pontos.
    nonisolated static let height: CGFloat = 60

    private static let tileSide: CGFloat = 44
    private static let tileCorner: CGFloat = 6
    /// O canto de fora acompanha o da miniatura: raio dela mais o recuo de 8 pt.
    private static let corner: CGFloat = tileCorner + 8
    /// Maior lado, em pixels, das imagens da miniatura.
    private static let imageMaxPixelSize = 176

    private var music: MusicSnapshot? {
        if case .music(let music) = card { return music }
        return nil
    }

    var body: some View {
        HStack(spacing: 10) {
            tile
                .frame(width: Self.tileSide, height: Self.tileSide)
                .clipShape(.rect(cornerRadius: Self.tileCorner))
            VStack(alignment: .leading, spacing: 2) {
                Text(title.isEmpty ? card.title : title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(music?.primaryTextColor ?? .primary)
                    .lineLimit(1)
                if let detail = EmbeddedCardWording.detail(for: card) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(music?.secondaryTextColor ?? .secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: Self.maximumWidth)
        .frame(height: Self.height)
        .background { background }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Partes

    @ViewBuilder
    private var tile: some View {
        switch card {
        case .music(let music):
            MusicArtwork(music: music, maxPixelSize: Self.imageMaxPixelSize)
        case .reminder(let reminder):
            EmbeddedReminderTile(reminder: reminder)
        case .link(let link):
            EmbeddedLinkTile(link: link, maxPixelSize: Self.imageMaxPixelSize)
        case .contact(let contact):
            ContactAvatar(contact: contact, diameter: Self.tileSide)
        }
    }

    /// O selo do tocador; sem ele, o símbolo do tipo, discreto.
    @ViewBuilder
    private var trailing: some View {
        if phase != .idle {
            EmbeddedCardPhaseBadge(phase: phase)
        } else {
            Image(systemName: card.itemKind.creationSymbol)
                .font(.caption)
                .foregroundStyle(music?.secondaryTextColor ?? .secondary)
                .padding(.trailing, 4)
                .accessibilityHidden(true)
        }
    }

    /// Música na cor da capa, como o cartão solto; os outros tipos num preenchimento neutro, que acompanha o claro e o escuro.
    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Self.corner)
        if let paper = music?.paperColor {
            shape.fill(paper)
        } else {
            shape.fill(.fill.quaternary)
        }
    }
}

/// O lembrete na miniatura da tira: a bolinha na cor da lista, cheia quando concluído.
private struct EmbeddedReminderTile: View {
    let reminder: ReminderSnapshot

    private var color: Color { reminder.isMissing ? .secondary : reminder.listColor }

    var body: some View {
        Circle()
            .strokeBorder(color, lineWidth: 1.5)
            .background(Circle().fill(reminder.isCompleted && !reminder.isMissing ? color : .clear))
            .overlay {
                if reminder.isCompleted {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
    }
}

/// O link na miniatura da tira: a imagem de prévia, se o arquivo está na pasta; sem ela, a inicial do site.
private struct EmbeddedLinkTile: View {
    let link: LinkInfo
    let maxPixelSize: Int

    @Environment(\.linkPreviewFiles) private var files

    var body: some View {
        if let name = link.previewImageFile, let url = files?.existingURL(for: name) {
            ThumbnailView(url: url, kind: .image, maxPixelSize: maxPixelSize)
        } else {
            Color(hue: LinkMonogram.hue(for: link.displayHost), saturation: 0.35, brightness: 0.82)
                .overlay {
                    Text(LinkMonogram.letter(for: link.displayHost))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }
        }
    }
}

#if DEBUG
private struct EmbeddedCardStripSamples: View {
    private static let cards: [EmbeddedCard] = [
        .music(
            MusicSnapshot(
                kind: .album, title: "Abbey Road", subtitle: "The Beatles", backgroundHex: "#1f3a5f", primaryTextHex: "#ffffff",
                secondaryTextHex: "#c9d6e8", trackCount: 17)),
        .reminder(ReminderSnapshot(identifier: "", title: "Comprar pão", listTitle: "Casa", listColorHex: "#FF9500")),
        .link(LinkInfo(url: URL(string: "https://www.apple.com/br/mac")!, pageTitle: "Mac", siteName: "Apple")),
        .contact(ContactSnapshot(givenName: "Fulana", familyName: "de Tal", organization: "Empresa")),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Self.cards, id: \.self) { card in
                EmbeddedCardStrip(card: card, title: card.title)
            }
            EmbeddedCardStrip(card: Self.cards[0], title: Self.cards[0].title, phase: .playing)
        }
        .padding(24)
        .frame(width: 400)
        .background(Theme.paper)
    }
}

#Preview("Tiras, claro", traits: .sizeThatFitsLayout) {
    EmbeddedCardStripSamples().preferredColorScheme(.light)
}

#Preview("Tiras, escuro", traits: .sizeThatFitsLayout) {
    EmbeddedCardStripSamples().preferredColorScheme(.dark)
}
#endif
