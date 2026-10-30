import Foundation
import MuralKit

/// Uma nota escrita no editor de texto, pronta para virar um cartão de texto num mural: o Markdown, os cartões embutidos que ele
/// cita (`![título](mural-card:<UUID>)`) e as imagens ainda só na memória (`![Colando imagem…](mural-colando:<TOKEN>)`).
struct PastedNote: Sendable {
    var text: String
    var embeds: [UUID: EmbeddedCard]
    var images: [UUID: NoteImagePaste.Source]

    init(text: String, embeds: [UUID: EmbeddedCard] = [:], images: [UUID: NoteImagePaste.Source] = [:]) {
        self.text = text
        self.embeds = embeds
        self.images = images
    }
}
