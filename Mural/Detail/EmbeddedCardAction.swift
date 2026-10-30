import Foundation
import MuralKit

/// O que o toque num cartão embutido faz na página de leitura.
enum EmbeddedCardAction: Equatable {
    /// Toca ou pausa a música no Apple Music.
    case toggleMusic
    /// Abre o endereço no navegador, já sem os parâmetros de rastreamento.
    case openLink(URL)

    /// A ação do cartão, ou `nil` quando ele só mostra o estado: lembrete, contato, música sem sessão para tocar e link que não é
    /// da web ou que a política de endereços não deixa abrir.
    static func action(for card: EmbeddedCard, canPlay: Bool) -> EmbeddedCardAction? {
        switch card {
        case .music:
            return canPlay ? .toggleMusic : nil
        case .link(let link):
            guard WebLink.isWeb(link.url) else { return nil }
            let url = WebLink.removingTrackingParameters(from: link.url)
            return ExternalURLPolicy.allowsOpening(url) ? .openLink(url) : nil
        case .reminder, .contact:
            return nil
        }
    }
}
