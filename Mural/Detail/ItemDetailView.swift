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
                Text("O cartão e o arquivo guardado pelo Mural serão removidos. O arquivo original não é tocado.")
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
        var actions = [PillAction(title: "Copiar", symbol: "square.on.square", perform: copyToPasteboard)]
        if let url = model.fileURL(for: item) {
            actions.append(
                PillAction(title: "Abrir no app padrão", symbol: "arrow.up.forward.app") {
                    NSWorkspace.shared.open(url)
                })
        }
        actions.append(PillAction(title: "Apagar", symbol: "trash", role: .destructive) { isConfirmingDelete = true })
        return actions
    }

    private func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let url = model.fileURL(for: item) {
            pasteboard.writeObjects([url as NSURL])
        } else if let checklist = item.checklist {
            pasteboard.setString(Self.plainText(of: checklist), forType: .string)
        } else {
            pasteboard.setString(item.text ?? item.title, forType: .string)
        }
    }

    /// Lista em texto simples, no mesmo formato que o mural reconhece ao colar.
    static func plainText(of document: ChecklistDocument) -> String {
        var lines = [document.title]
        if !document.intro.isEmpty { lines.append(document.intro) }
        for section in document.sections {
            if !section.title.isEmpty { lines.append(section.title) }
            lines += section.entries.map { "- [\($0.isDone ? "x" : " ")] \($0.text)" }
        }
        return lines.joined(separator: "\n")
    }
}
