import AppKit
import MuralKit
import SwiftUI

/// Desenha o conteúdo de um anexo do editor como imagem (`EmbeddedTextAttachment.Picture`): a tira do cartão, nas duas aparências,
/// ou a imagem colada, com o canto arredondado.
@MainActor
enum EditorAttachmentPicture {
    /// Pixels por ponto: o desenho precisa ficar nítido nas telas Retina, e nas outras é reduzido.
    private static let scale: CGFloat = 2

    static func make(for content: EmbeddedTextAttachment.Content) -> EmbeddedTextAttachment.Picture {
        let width = EmbeddedTextAttachment.maximumWidth
        let size = CGSize(width: width, height: (width * EmbeddedTextAttachment.heightRatio(of: content)).rounded())
        switch content {
        case .card(let card, let title):
            let label = EmbeddedCardWording.label(for: card, title: title)
            let strip = EmbeddedCardStrip(card: card, title: title)
            return EmbeddedTextAttachment.Picture(
                light: render(strip.environment(\.colorScheme, .light), size: size, label: label),
                dark: render(strip.environment(\.colorScheme, .dark), size: size, label: label))
        case .image(let image, let alt):
            let view = EditorImageAttachmentView(image: image, alt: alt)
            let picture = render(view, size: size, label: alt.isEmpty ? "Imagem" : alt)
            return EmbeddedTextAttachment.Picture(light: picture, dark: picture)
        }
    }

    private static func render(_ view: some View, size: CGSize, label: String) -> NSImage {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height, alignment: .topLeading))
        renderer.scale = scale
        let image = renderer.cgImage.map { NSImage(cgImage: $0, size: size) } ?? NSImage(size: size)
        image.accessibilityDescription = label
        return image
    }
}
