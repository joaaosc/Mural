import MuralKit
import StretchTextUI
import SwiftUI

/// Escolhe o visual de um cartão pelo tipo de conteúdo.
struct CardView: View {
    let item: BoardItem
    let model: BoardModel

    @Environment(\.linkPreviewFiles) private var linkPreviewFiles

    var body: some View {
        switch item.kind {
        case .text:
            PaperCard(title: item.title, summary: model.foldedText(for: item), tint: item.colorTag)
                .stretchMarkdownImage { NoteImageView(image: $0, item: item, model: model, maxPixelSize: 240) }
        case .sticky:
            StickyCard(text: item.displayText, color: item.stickyColor)
                .colorTagDot(item.colorTag)
        case .checklist:
            ChecklistCard(document: item.checklistDocument, tint: item.colorTag)
        case .link:
            LinkCard(item: item)
                .colorTagDot(item.colorTag)
        case .reminder:
            if let reminder = item.reminder {
                ReminderCard(reminder: reminder)
                    .colorTagDot(item.colorTag)
            }
        case .music:
            MusicCard(item: item)
                .colorTagDot(item.colorTag)
        case .image, .video, .pdf:
            let url = model.fileURL(for: item)
            // A foto sempre preenche o cartão. No tamanho com a proporção do arquivo ("Foto inteira"), preencher já mostra a
            // imagem toda; em qualquer outro, o recorte é o mesmo durante o arrasto do canto e depois dele.
            MediaCard(url: url, kind: item.kind, previewVideoURL: item.kind == .video ? url : nil)
                .colorTagDot(item.colorTag)
        case .folder:
            let children = model.children(of: item.id)
            FolderCard(
                folder: item,
                itemCount: children.count,
                peeks: FolderPeekItem.latest(
                    children, fileURL: model.fileURL(for:),
                    linkPreviewURL: { FolderPeekItem.linkPreviewURL(of: $0, in: linkPreviewFiles) })
            )
        }
    }
}
