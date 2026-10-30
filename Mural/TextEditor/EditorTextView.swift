import AppKit

/// O `NSTextView` do editor de texto: prosa em TextKit 2, com anexos de cartão e de imagem, que interpreta o colar
/// (`TextEditorPasteReader`) antes do texto simples.
///
/// Esc não faz nada aqui: quem fecha o editor é a janela.
final class EditorTextView: MarkdownSourceTextView {
    /// Chamado com o que o colar trouxe; devolve `true` quando tratou (cartões, imagens, texto com linhas de cartão). Texto simples
    /// e nada seguem o caminho do `NSTextView`.
    var onPaste: ((TextEditorPaste) -> Bool)?

    /// A ponte dos anexos: com ela, copiar, recortar e arrastar um trecho com anexos leva o Markdown deles.
    weak var bridge: EditorAttachmentBridge?

    /// Um campo de texto de prosa com TextKit 2. Nunca leia `layoutManager` ou `textContainer.layoutManager`: a view voltaria ao
    /// TextKit 1 para sempre, e os anexos só sabem o próprio tamanho no TextKit 2.
    static func make() -> EditorTextView {
        let textView = EditorTextView(usingTextLayoutManager: true)
        textView.configure()
        return textView
    }

    private func configure() {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        isContinuousSpellCheckingEnabled = true
        isGrammarCheckingEnabled = true
        writingToolsBehavior = .complete
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        drawsBackground = false
        textContainerInset = NSSize(width: 16, height: 16)
        textContainer?.lineFragmentPadding = 0

        let font = NSFont.preferredFont(forTextStyle: .body)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        self.font = font
        textColor = .labelColor
        defaultParagraphStyle = style
        typingAttributes = [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: style]
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        var types = super.readablePasteboardTypes
        types += TextEditorPasteReader.extraTypes.filter { !types.contains($0) }
        return types
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if handlePaste(from: pboard) { return true }
        return super.readSelection(from: pboard, type: type)
    }

    /// Com anexos na seleção só o texto sai, e é o Markdown do trecho: o cartão não sobrevive a um RTF, e colado de volta no editor
    /// a linha vira o anexo de novo (`TextEditorDocument.paste`).
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        if let bridge, bridge.containsAttachment(in: selectedRange()) { return [.string] }
        return super.writablePasteboardTypes
    }

    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard let bridge, bridge.containsAttachment(in: selectedRange()) else {
            return super.writeSelection(to: pboard, type: type)
        }
        guard type == .string else { return false }
        pboard.setString(bridge.markdown(of: selectedRange()), forType: .string)
        return true
    }

    private func handlePaste(from pasteboard: NSPasteboard) -> Bool {
        guard let onPaste else { return false }
        switch TextEditorPasteReader.read(from: pasteboard) {
        case .nothing:
            return false
        case let paste:
            // O texto também passa por `onPaste`: se traz linhas de cartão do próprio editor, elas voltam a ser anexos.
            return onPaste(paste)
        }
    }
}
