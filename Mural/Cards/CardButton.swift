import MuralKit
import SwiftUI

/// Cartão clicável do mural, da prévia de pasta e de dentro da pasta: abre o item,
/// participa da transição de "crescer do cartão" e oferece Abrir, Mover e Apagar… no menu de
/// contexto, com confirmação antes de apagar.
struct CardButton: View {
    let item: BoardItem
    let model: BoardModel
    let hero: HeroContext
    var onOpen: () -> Void
    var onDelete: ((UUID) -> Void)? = nil
    var onMoveToBoard: ((UUID) -> Void)? = nil
    var onMoveIntoFolder: ((UUID, UUID) -> Void)? = nil

    @State private var isConfirmingDelete = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HeroSlot(id: item.id, context: hero) {
            Button(action: onOpen) {
                CardView(item: item, model: model)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.title)
            .contextMenu {
                Button("Abrir", action: onOpen)
                moveMenu
                Divider()
                Button("Apagar…", role: .destructive) { isConfirmingDelete = true }
            }
            .confirmationDialog("Apagar “\(item.title)”?", isPresented: $isConfirmingDelete) {
                Button("Apagar", role: .destructive) {
                    withAnimation(reduceMotion ? nil : .smooth) { onDelete?(item.id) ?? model.delete(item.id) }
                }
            } message: {
                Text(ItemKind.deleteWarning(for: item, childCount: model.children(of: item.id).count))
            }
        }
    }

    /// Alternativa ao arrasto: guardar um cartão solto numa pasta ou devolver ao mural um cartão
    /// de dentro da pasta.
    @ViewBuilder
    private var moveMenu: some View {
        if item.parentID != nil {
            Button("Mover para o mural") {
                withAnimation(reduceMotion ? nil : .smooth) { onMoveToBoard?(item.id) ?? model.moveToBoard(item.id) }
            }
        } else if item.kind != .folder {
            let folders = model.rootItems.filter { $0.kind == .folder }
            if !folders.isEmpty {
                Menu("Mover para a pasta") {
                    ForEach(folders) { folder in
                        Button(folder.title) {
                            withAnimation(reduceMotion ? nil : .smooth) {
                                onMoveIntoFolder?(item.id, folder.id) ?? model.moveIntoFolder(item.id, folderID: folder.id)
                            }
                        }
                    }
                }
            }
        }
    }
}
