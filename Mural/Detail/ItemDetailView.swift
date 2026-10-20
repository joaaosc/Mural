import AppKit
import MuralKit
import SwiftUI

/// Nível 3: escolhe a tela de detalhe pelo tipo e mostra a pílula de ações.
struct ItemDetailView: View {
    let item: BoardItem
    let model: BoardModel
    var onClose: () -> Void

    @State private var isConfirmingDelete = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                ActionPill(actions: actions)
                    .padding(.bottom, 22)
            }
            .confirmationDialog("Apagar “\(item.title)”?", isPresented: $isConfirmingDelete) {
                Button("Apagar", role: .destructive) {
                    onClose()
                    model.delete(item.id)
                }
            } message: {
                Text(ItemKind.deleteWarning(for: item, childCount: 0))
            }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .image:
            ImageDetailView(item: item, model: model)
        case .video:
            VideoDetailView(url: model.fileURL(for: item), title: item.title)
        case .pdf:
            PDFDetailView(url: model.fileURL(for: item))
        case .text, .sticky:
            TextDetailView(item: item)
        case .checklist:
            ChecklistDetailView(item: item, model: model)
        case .folder:
            EmptyView()
        }
    }

    private var actions: [PillAction] {
        var actions = [
            PillAction(title: "Copiar", symbol: "square.on.square") { PasteboardExporter.copy(item, from: model) }
        ]
        if let url = model.fileURL(for: item) {
            actions.append(
                PillAction(title: "Abrir no app padrão", symbol: "arrow.up.forward.app") {
                    NSWorkspace.shared.open(url)
                })
        }
        actions.append(PillAction(title: "Apagar", symbol: "trash", role: .destructive) { isConfirmingDelete = true })
        return actions
    }
}
