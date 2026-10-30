import Foundation
import MuralKit

/// Os textos de acessibilidade de um cartão embutido numa nota. Funções puras, para serem conferidas sem desenhar nada.
enum EmbeddedCardWording {
    /// O nome do tipo, como a leitura de tela o diz.
    static func kindName(of card: EmbeddedCard) -> String {
        switch card {
        case .music: "Música"
        case .reminder: "Lembrete"
        case .link: "Link"
        case .contact: "Contato"
        }
    }

    /// "<tipo>, <título>": "Música, Abbey Road".
    static func label(for card: EmbeddedCard, title: String) -> String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? kindName(of: card) : "\(kindName(of: card)), \(name)"
    }

    /// O que o botão faz; `nil` para o cartão que só mostra o estado (lembrete e contato).
    static func hint(for card: EmbeddedCard) -> String? {
        switch card {
        case .music: "Toca ou pausa no Apple Music."
        case .link: "Abre o endereço no navegador."
        case .reminder, .contact: nil
        }
    }

    /// O valor de acessibilidade da música embutida: "tocando", "pausado" ou nada.
    static func playbackValue(for phase: MusicCardPhase) -> String {
        switch phase {
        case .playing: "tocando"
        case .paused: "pausado"
        case .idle, .loading: ""
        }
    }
}
