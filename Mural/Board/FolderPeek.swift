import MuralKit
import SwiftUI

/// Prévia de uma pasta ao passar o ponteiro: até seis cartões de dentro, lado a lado.
struct FolderPeek: View {
    let folder: BoardItem
    let model: BoardModel
    let hero: HeroContext
    var onOpenChild: (UUID) -> Void

    var body: some View {
        let children = Array(model.children(of: folder.id).prefix(6))
        HStack(alignment: .top, spacing: 10) {
            ForEach(children) { child in
                let size = BoardLayout.cardSize(for: child.kind)
                HeroSlot(id: child.id, context: hero) {
                    Button {
                        onOpenChild(child.id)
                    } label: {
                        CardView(item: child, model: model)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(child.title)
                }
                .frame(width: size.width * 0.8, height: size.height * 0.8)
            }
            if children.isEmpty {
                Text("Pasta vazia — abra e cole algo com ⌘V")
                    .font(.label)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
    }
}
