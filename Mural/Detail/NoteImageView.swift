import MuralKit
import StretchText
import StretchTextUI
import SwiftUI

/// Imagem colada numa nota, no lugar da linha `![alt](arquivo)` do Markdown; para `mural-card:`, o cartão embutido.
///
/// A moldura tem a proporção do anexo desde o primeiro layout, para que a altura
/// da página não dependa do carregamento (a restauração da rolagem depende dela).
struct NoteImageView: View {
    let image: MarkdownImage
    let item: BoardItem
    let model: BoardModel?
    let maxPixelSize: Int
    /// A sessão da janela, quando a nota está na página de leitura: é ela que toca a música embutida.
    var session: BoardWindowSession?

    var body: some View {
        if NoteImageMarkup.isPendingSource(image.source) {
            pending
        } else if NoteImageMarkup.isCardSource(image.source) {
            if let id = NoteImageMarkup.cardID(inSource: image.source), let card = item.embeddedCard(id: id) {
                EmbeddedCardView(
                    card: card, cardID: id, title: image.alt, item: item, model: model, maxPixelSize: maxPixelSize,
                    session: session)
            } else {
                Label(image.alt, systemImage: "questionmark.square.dashed")
                    .foregroundStyle(.secondary)
            }
        } else if let url = fileURL {
            Color.clear
                .aspectRatio(aspectRatio, contentMode: .fit)
                .overlay {
                    ThumbnailView(url: url, kind: .image, maxPixelSize: maxPixelSize, contentMode: .fit)
                }
                .clipShape(.rect(cornerRadius: Theme.cardCorner))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(image.alt.isEmpty ? "Imagem" : image.alt)
                .accessibilityAddTraits(.isImage)
        } else {
            Label(image.alt, systemImage: "photo")
                .foregroundStyle(.secondary)
        }
    }

    private var pending: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Colando imagem…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(.quaternary, in: .rect(cornerRadius: Theme.cardCorner))
    }

    /// Só anexos seguros cujo arquivo existe em `Items/`.
    private var fileURL: URL? {
        guard let url = model?.noteImageURL(named: image.source),
            FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    private var aspectRatio: CGFloat {
        guard let attachment = item.attachments?.first(where: { $0.fileName == image.source }),
            attachment.pixelWidth > 0, attachment.pixelHeight > 0
        else { return 4.0 / 3.0 }
        return CGFloat(attachment.pixelWidth) / CGFloat(attachment.pixelHeight)
    }
}
