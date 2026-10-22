import AppKit
import MuralKit
import SwiftUI

/// Edição da nota na própria página: título num campo e corpo em Markdown, em
/// fonte monoespaçada. ⌘B e ⌘I (menu Formatar) aplicam negrito e itálico na seleção.
///
/// O texto vai para o rascunho da sessão a cada mudança e só entra no mural ao
/// concluir, ao sair da página ou ao fechar a janela.
struct NoteEditorView: View {
    let itemID: UUID
    let session: BoardWindowSession

    @State private var draft: NoteDraft
    @State private var controller = NoteBodyEditorController()
    @State private var keyMonitor: Any?
    @FocusState private var titleFocused: Bool

    init(itemID: UUID, session: BoardWindowSession) {
        self.itemID = itemID
        self.session = session
        _draft = State(initialValue: session.noteDraft(for: itemID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Título", text: $draft.title)
                .textFieldStyle(.plain)
                .font(.system(size: 40, weight: .bold))
                .focused($titleFocused)
                .onSubmit { controller.focus() }
            NoteBodyEditor(
                text: $draft.text, controller: controller, onImages: receiveImages,
                onEscape: { session.finishEditing() })
            Text("Markdown: # título, - lista, - [ ] tarefa, > citação, **negrito**, *itálico*, imagem: ⌘V.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .focusedSceneValue(
            \.markdownFormatting,
            controller.isFirstResponder ? MarkdownFormattingAction(apply: controller.toggle) : nil
        )
        .onChange(of: draft) { _, newDraft in
            session.setNoteDraft(newDraft, for: itemID)
        }
        .onKeyPress(.escape) {
            session.finishEditing()
            return .handled
        }
        .onAppear {
            focusFirstField()
            installPasteMonitor()
        }
        .onDisappear(perform: removePasteMonitor)
    }

    /// Nota nova começa pelo título; nota existente, pelo fim do corpo.
    private func focusFirstField() {
        if draft.title.isEmpty && draft.text.isEmpty {
            // No `onAppear` a página ainda está entrando e o campo recusa o foco: o pedido vai na volta seguinte.
            Task { @MainActor in titleFocused = true }
        } else {
            controller.focus(atEnd: true)
        }
    }

    /// Grava as imagens coladas e troca cada marcador pela linha final (ou o remove se falhou).
    private func receiveImages(_ pending: [(token: UUID, source: NoteImagePaste.Source)]) {
        guard !pending.isEmpty else { return }
        let session = session
        let itemID = itemID
        let controller = controller
        Task {
            let attachments = await session.prepareNoteImages(pending.map(\.source), for: itemID)
            for (index, entry) in pending.enumerated() {
                let markdown =
                    attachments.indices.contains(index) ? attachments[index].map { NoteImageMarkup.line(fileName: $0.fileName) } ?? "" : ""
                if !controller.replacePending(entry.token, with: markdown) {
                    session.replacePendingImage(entry.token, with: markdown, in: itemID)
                }
            }
        }
    }

    /// ⌘V com uma imagem na área de transferência e o cursor fora do corpo (no título, ou em texto
    /// nenhum depois de um clique na página): a imagem vai para o fim do corpo, não para um cartão novo.
    private func installPasteMonitor() {
        removePasteMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [controller] event in
            // Só nesta janela e fora do corpo, que cola sozinho; de um campo de texto (o título) a imagem também sai.
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                event.charactersIgnoringModifiers == "v",
                let textView = controller.textView, let window = textView.window, event.window === window,
                window.firstResponder !== textView, (window.firstResponder as? NSTextView)?.isFieldEditor ?? true,
                let pieces = NoteImagePaste.read(from: .general)
            else { return event }
            receiveImages(controller.appendAtEnd(pieces))
            controller.focus()
            return nil
        }
    }

    private func removePasteMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
