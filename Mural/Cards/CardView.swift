import MuralKit
import SwiftUI

/// Escolhe o visual de um cartão pelo tipo de conteúdo.
struct CardView: View {
    let item: BoardItem
    let model: BoardModel

    @Environment(\.linkPreviewFiles) private var linkPreviewFiles

    var body: some View {
        switch item.kind {
        case .text:
            PaperCard(title: item.title, summary: NoteFolding.fold(for: item))
        case .sticky:
            StickyCard(text: item.displayText, color: item.stickyColor)
        case .checklist:
            ChecklistCard(document: item.checklistDocument)
        case .link:
            LinkCard(item: item)
        case .image, .video, .pdf:
            MediaCard(url: model.fileURL(for: item), kind: item.kind)
        case .folder:
            let children = model.children(of: item.id)
            FolderCard(
                folder: item,
                itemCount: children.count,
                peeks: FolderPeekItem.latest(
                    children, fileURL: model.fileURL(for:),
                    linkPreviewURL: { child in
                        child.link?.previewImageFile.flatMap { name in linkPreviewFiles.map { $0.url(for: name) } }
                    })
            )
        }
    }
}
