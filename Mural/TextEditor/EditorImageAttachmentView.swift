import AppKit
import SwiftUI

/// A imagem colada no editor, ainda só na memória: cabe na largura do anexo, com o canto arredondado dos cartões.
struct EditorImageAttachmentView: View {
    let image: NSImage?
    let alt: String

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: EmbeddedTextAttachment.maximumWidth, alignment: .leading)
        .clipShape(.rect(cornerRadius: Theme.cardCorner))
        .accessibilityLabel(alt.isEmpty ? "Imagem" : alt)
        .accessibilityAddTraits(.isImage)
    }
}
