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
            PaperCard(title: item.title, summary: NoteFolding.fold(for: item), tint: item.colorTag)
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
            MediaCard(url: model.fileURL(for: item), kind: item.kind)
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
