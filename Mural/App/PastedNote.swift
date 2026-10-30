import Foundation
import MuralKit

/// Uma nota escrita no editor de texto, pronta para virar um cartão de texto num mural: o Markdown, os cartões embutidos que ele
/// cita (`![título](mural-card:<UUID>)`) e as imagens ainda só na memória (`![Colando imagem…](mural-colando:<TOKEN>)`).
struct PastedNote: Sendable {
    var text: String
    var embeds: [UUID: EmbeddedCard]
    var images: [UUID: NoteImagePaste.Source]
    /// O título que a pessoa deu ao cartão; `nil` deixa o título sair do texto.
    var title: String?

    init(text: String, embeds: [UUID: EmbeddedCard] = [:], images: [UUID: NoteImagePaste.Source] = [:], title: String? = nil) {
        self.text = text
        self.embeds = embeds
        self.images = images
        self.title = title
    }
}
