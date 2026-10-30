import AppKit
import MuralKit
import SwiftUI

/// O campo de texto do editor: `EditorTextView` com a ponte dos anexos, ligado ao `TextEditorDocument`.
struct TextEditorBody: NSViewRepresentable {
    let document: TextEditorDocument

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = EditorTextView.make()
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityLabel("Texto do cartão")

        context.coordinator.install(in: textView)
        textView.delegate = context.coordinator
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        context.coordinator.bridge.reload(document.text)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.document !== document {
            // Outro documento: a ponte e o colar passam a servi-lo, e o campo mostra o texto dele.
            coordinator.document = document
            if let textView = scrollView.documentView as? EditorTextView { coordinator.install(in: textView) }
            coordinator.bridge.reload(document.text)
        }
        // O documento mudou por fora (limpar, abrir): o campo refaz o texto. Mudanças do próprio campo já chegaram ao documento.
        if coordinator.bridge.markdown() != document.text { coordinator.bridge.reload(document.text) }
    }

    /// Leva as mudanças do campo (texto e seleção) para o documento, guarda o desfazer do campo e diz às Ferramentas de Escrita
    /// quais trechos são anexos.
    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var document: TextEditorDocument
        let bridge: EditorAttachmentBridge
        /// O desfazer do campo, só dele: recarregar o texto limpa este e nenhum outro.
        private let undo = UndoManager()

        init(document: TextEditorDocument) {
            self.document = document
            self.bridge = EditorAttachmentBridge { _ in nil }
            super.init()
            bridge.resolve = { [weak self] line in self?.document.content(forLine: line) }
        }

        /// Liga o campo à ponte e ao documento atual.
        func install(in textView: EditorTextView) {
            bridge.attach(textView)
            textView.bridge = bridge
            document.attach(bridge)
            textView.onPaste = { [weak self] paste in self?.document.paste(paste) ?? false }
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            undo
        }

        func textDidChange(_ notification: Notification) {
            sync()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            sync()
        }

        /// Os anexos ficam fora das reescritas das Ferramentas de Escrita.
        func textView(_ textView: NSTextView, writingToolsIgnoredRangesInEnclosingRange enclosingRange: NSRange) -> [NSValue] {
            bridge.attachmentRanges(in: enclosingRange)
        }

        /// O texto e a seleção saem do mesmo mapa (`EditorAttachmentBridge.currentMapping`), que só é refeito depois de uma edição.
        private func sync() {
            document.sync(markdown: bridge.markdown(), selectionUTF16: bridge.markdownSelection())
        }
    }
}

#if DEBUG
/// Um documento com um cartão e uma imagem, como o editor os mostra.
private struct TextEditorBodySample: View {
    @State private var document: TextEditorDocument = {
        let document = TextEditorDocument()
        document.text = "Visita à obra.\n\n"
        let contact = EmbeddedCard.contact(ContactSnapshot(givenName: "Fulana", familyName: "de Tal", organization: "Empresa"))
        document.insertCards([contact])
        return document
    }()

    var body: some View {
        TextEditorBody(document: document)
            .frame(width: 520, height: 420)
    }
}

#Preview("Editor de texto") {
    TextEditorBodySample()
}
#endif
