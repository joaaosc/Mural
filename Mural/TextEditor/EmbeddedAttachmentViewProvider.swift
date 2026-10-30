import AppKit
import MuralKit
import SwiftUI

/// A view de um `EmbeddedTextAttachment` dentro do texto: o cartão desenhado como na nota (`EmbeddedCardStrip`) ou a imagem
/// colada. A view recebe os eventos direto, e a altura acompanha o que o anexo calcula.
nonisolated final class EmbeddedAttachmentViewProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        guard let attachment = textAttachment as? EmbeddedTextAttachment else { return }
        // O TextKit chama `loadView` na thread principal.
        let content = attachment.content
        view = MainActor.assumeIsolated { Self.makeView(for: content) }
    }

    @MainActor
    private static func makeView(for content: EmbeddedTextAttachment.Content) -> NSView {
        switch content {
        case .card(let card, let title):
            return NSHostingView(rootView: EmbeddedCardStrip(card: card, title: title))
        case .image(let image, let alt):
            return NSHostingView(rootView: EditorImageAttachmentView(image: image, alt: alt))
        }
    }
}
