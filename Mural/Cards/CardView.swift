import MuralKit
import SwiftUI

/// Escolhe o visual de um cartão pelo tipo de conteúdo.
struct CardView: View {
    let item: BoardItem
    let model: BoardModel

    var body: some View {
        switch item.kind {
        case .text:
            PaperCard(title: item.title, summary: NoteFolding.fold(for: item))
        case .sticky:
            StickyCard(text: item.displayText, color: item.stickyColor)
        case .checklist:
            ChecklistCard(document: item.checklistDocument)
        case .image, .video, .pdf:
            MediaCard(url: model.fileURL(for: item), kind: item.kind)
        case .folder:
            let children = model.children(of: item.id)
            FolderCard(
                folder: item,
                itemCount: children.count,
                peeks: FolderPeekItem.latest(children, fileURL: model.fileURL(for:))
            )
        }
    }
}
