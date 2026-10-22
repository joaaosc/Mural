import MuralKit
import SwiftUI

/// Detalhes da pasta mostrados pelo botão de informação.
struct FolderInfoView: View {
    let folder: BoardItem
    let children: [BoardItem]

    var body: some View {
        Form {
            LabeledContent("Nome", value: folder.title)
            if let tag = folder.tag {
                LabeledContent("Etiqueta", value: tag)
            }
            if let color = folder.colorTag {
                LabeledContent("Cor") {
                    HStack(spacing: 6) {
                        ColorTagDot(color: color)
                        Text(color.displayName)
                    }
                }
            }
            LabeledContent("Conteúdo", value: ItemKind.summary(of: children))
            LabeledContent("Criada em") {
                Text(folder.createdAt, format: .dateTime.day().month(.twoDigits).year())
            }
        }
        .formStyle(.grouped)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    let board = SampleBoard.make()
    let folder = board.rootItems.first { $0.kind == .folder }!
    FolderInfoView(folder: folder, children: board.children(of: folder.id))
}
