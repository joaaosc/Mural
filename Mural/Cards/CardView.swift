import MuralKit
import SwiftUI

/// Escolhe o visual de um cartão pelo tipo de conteúdo.
struct CardView: View {
    let item: BoardItem
    let model: BoardModel

    var body: some View {
        switch item.kind {
        case .text:
            PaperCard(title: item.title, text: item.text ?? "")
        case .sticky:
            StickyCard(text: item.text ?? item.title, color: item.stickyColor)
        case .checklist:
            ChecklistCard(document: item.checklist ?? ChecklistDocument(title: item.title, sections: []))
        case .image, .video, .pdf:
            MediaCard(url: model.fileURL(for: item), kind: item.kind)
        case .folder:
            let children = model.children(of: item.id)
            let peek = children.first { $0.kind == .image || $0.kind == .video }
            FolderCard(
                folder: item,
                itemCount: children.count,
                peekURL: peek.flatMap(model.fileURL(for:)),
                peekKind: peek?.kind
            )
        }
    }

    /// Proporção largura ÷ altura usada na grade das coleções.
    static func aspectRatio(for item: BoardItem) -> CGFloat {
        if item.kind == .image, let meta = item.imageMetadata, meta.pixelHeight > 0 {
            return CGFloat(meta.pixelWidth) / CGFloat(meta.pixelHeight)
        }
        return switch item.kind {
        case .image: 0.75
        case .video: 0.8
        case .pdf: 0.77
        case .text, .checklist, .folder: 0.72
        case .sticky: 1.25
        }
    }
}
