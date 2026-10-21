import AppKit
import MuralKit
import SwiftUI

/// Nível 3: escolhe a tela de detalhe pelo tipo e mostra a pílula de ações (o link tem a própria).
struct ItemDetailView: View {
    let item: BoardItem
    let model: BoardModel
    let session: BoardWindowSession?
    var onClose: () -> Void

    @State private var isConfirmingDelete = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if item.kind != .link {
                    ActionPill(actions: actions)
                        .padding(.bottom, 22)
                }
            }
            .confirmationDialog("Apagar “\(item.title)”?", isPresented: $isConfirmingDelete) {
                Button("Apagar", role: .destructive) {
                    onClose()
                    if let session { session.delete(item.id) } else { model.delete(item.id) }
                }
            } message: {
                Text(ItemKind.deleteWarning(for: item, childCount: 0))
            }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .image:
            ImageDetailView(item: item, model: model, session: session)
        case .video:
            VideoDetailView(url: model.fileURL(for: item), title: item.title)
        case .pdf:
            PDFDetailView(itemID: item.id, url: model.fileURL(for: item), session: session)
        case .text, .sticky:
            TextDetailView(item: item, session: session)
        case .link:
            LinkDetailView(item: item, model: model) { isConfirmingDelete = true }
        case .checklist:
            ChecklistDetailView(item: item, model: model, session: session)
        case .folder:
            EmptyView()
        }
    }

    private var actions: [PillAction] {
        var actions: [PillAction] = []
        if let session, item.kind == .text || item.kind == .sticky {
            if session.editingItemID == item.id {
                actions.append(
                    PillAction(title: "Concluir", symbol: "checkmark", shortcut: KeyboardShortcut(.return, modifiers: .command)) {
                        session.finishEditing()
                    })
            } else {
                actions.append(
                    PillAction(title: "Editar", symbol: "pencil", shortcut: KeyboardShortcut("e", modifiers: .command)) {
                        session.beginEditing(item.id)
                    })
            }
        }
        actions.append(PillAction(title: "Copiar", symbol: "square.on.square") { PasteboardExporter.copy(item, from: model) })
        if let url = model.fileURL(for: item) {
            actions.append(
                PillAction(title: "Abrir no app padrão", symbol: "arrow.up.forward.app") {
                    NSWorkspace.shared.open(url)
                })
        }
        if let url = item.browserURL {
            actions.append(PillAction(title: "Abrir no navegador", symbol: "safari") { NSWorkspace.shared.open(url) })
        }
        actions.append(PillAction(title: "Apagar", symbol: "trash", role: .destructive) { isConfirmingDelete = true })
        return actions
    }
}
