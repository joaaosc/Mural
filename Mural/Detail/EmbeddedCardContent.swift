import MuralKit
import SwiftUI

/// O desenho de um cartão embutido numa nota: o mesmo conteúdo do cartão solto do tipo, a partir do estado guardado no anexo.
/// Preenche o espaço que recebe, que deve ter a proporção do tipo (`BoardLayout.cardSize(for:)`).
struct EmbeddedCardContent: View {
    let card: EmbeddedCard
    let title: String
    /// Maior lado, em pixels, da capa ou da imagem de prévia.
    var imageMaxPixelSize = 480

    var body: some View {
        switch card {
        case .music(let music):
            MusicCardContent(music: music, title: title, artworkMaxPixelSize: imageMaxPixelSize)
        case .reminder(let reminder):
            ReminderCard(reminder: reminder)
        case .link(let link):
            LinkCardContent(link: link, title: title, imageMaxPixelSize: imageMaxPixelSize)
        case .contact(let contact):
            ContactCard(contact: contact)
        }
    }
}
