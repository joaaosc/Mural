import MuralKit
import SwiftUI

/// O conteúdo de um cartão embutido no tamanho natural do cartão solto (`BoardLayout.cardSize(for:)`), reduzido para caber na
/// largura que a nota oferece, com no máximo 320 pt, e alinhado à esquerda. A altura vem da proporção do tipo.
struct EmbeddedCardScaledContent: View {
    let card: EmbeddedCard
    let title: String
    /// O estado do tocador, quando o cartão é uma música embutida; mostra o selo de tocando ou pausado.
    var phase: MusicCardPhase = .idle

    /// Largura máxima do cartão embutido, em pontos.
    static let maximumWidth: CGFloat = 320

    private var naturalSize: CGSize {
        let size = BoardLayout.cardSize(for: card.itemKind)
        return CGSize(width: size.width, height: size.height)
    }

    /// Lado, em pixels, das imagens do cartão: 480 no tamanho natural, em proporção à ampliação (e à tela retina), até 1600.
    static func imagePixelSize(scale: CGFloat) -> Int {
        min(1_600, max(480, Int(480 * scale * 2)))
    }

    var body: some View {
        Color.clear
            .aspectRatio(naturalSize.width / naturalSize.height, contentMode: .fit)
            .frame(maxWidth: Self.maximumWidth)
            .overlay {
                GeometryReader { proxy in
                    let scale = proxy.size.width / naturalSize.width
                    EmbeddedCardContent(card: card, title: title, imageMaxPixelSize: Self.imagePixelSize(scale: scale))
                        .frame(width: naturalSize.width, height: naturalSize.height)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                        .overlay(alignment: .topTrailing) {
                            if phase != .idle { EmbeddedCardPhaseBadge(phase: phase) }
                        }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
