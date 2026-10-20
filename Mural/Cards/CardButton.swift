import MuralKit
import SwiftUI

/// Cartão clicável do mural, da prévia de pasta e de dentro da pasta: abre o item,
/// participa da transição de "crescer do cartão" e oferece Abrir e Apagar… no menu de
/// contexto, com confirmação antes de apagar.
struct CardButton: View {
    let item: BoardItem
    let model: BoardModel
    let hero: HeroContext
    var onOpen: () -> Void

    @State private var isConfirmingDelete = false

    var body: some View {
        HeroSlot(id: item.id, context: hero) {
            Button(action: onOpen) {
                CardView(item: item, model: model)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.title)
            .contextMenu {
                Button("Abrir", action: onOpen)
                Divider()
                Button("Apagar…", role: .destructive) { isConfirmingDelete = true }
            }
            .confirmationDialog("Apagar “\(item.title)”?", isPresented: $isConfirmingDelete) {
                Button("Apagar", role: .destructive) {
                    withAnimation(.smooth) { model.delete(item.id) }
                }
            } message: {
                Text(ItemKind.deleteWarning(for: item, childCount: model.children(of: item.id).count))
            }
        }
    }
}
