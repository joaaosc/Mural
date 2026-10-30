import AppKit
import MuralKit
import SwiftUI

/// Liga o texto do corpo da nota (AppKit) ao restante do editor: foco, negrito/itálico e inserção de
/// imagens, tudo pelo caminho de edição do `NSTextView` para que o ⌘Z desfaça.
@MainActor @Observable
final class NoteBodyEditorController {
    /// Verdadeiro enquanto o texto do corpo é o primeiro respondedor.
    private(set) var isFirstResponder = false

    @ObservationIgnored private(set) weak var textView: NSTextView?
    @ObservationIgnored private var focusRequest: FocusRequest?

    private struct FocusRequest {
        let atEnd: Bool
    }

    /// Chamado pelo editor ao montar o `NSTextView`.
    func attach(_ textView: NSTextView) {
        self.textView = textView
        performPendingFocus()
    }

    func setFirstResponder(_ value: Bool) {
        if isFirstResponder != value { isFirstResponder = value }
    }

    /// Faz o texto virar primeiro respondedor; se ainda não está numa janela, faz quando entrar.
    func focus(atEnd: Bool = false) {
        focusRequest = FocusRequest(atEnd: atEnd)
        performPendingFocus()
    }

    /// Tenta atender o pedido de foco guardado; chamado também quando o texto entra numa janela.
    func performPendingFocus() {
        guard let request = focusRequest, let textView, let window = textView.window else { return }
        focusRequest = nil
        if request.atEnd { textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0)) }
        window.makeFirstResponder(textView)
    }

    // MARK: Edição

    /// Negrito ou itálico na seleção, sobre o texto atual; o ⌘Z desfaz.
    func toggle(_ emphasis: MarkdownEmphasis) {
        guard let textView else { return }
        let text = textView.string
        let range = Range(textView.selectedRange(), in: text) ?? text.endIndex..<text.endIndex
        let lower = text.distance(from: text.startIndex, to: range.lowerBound)
        let upper = text.distance(from: text.startIndex, to: range.upperBound)
        let result = emphasis.toggle(in: text, selection: lower..<upper)
        replaceString(with: result.text, in: textView)
        let newText = textView.string
        let start =
            newText.index(newText.startIndex, offsetBy: result.selection.lowerBound, limitedBy: newText.endIndex) ?? newText.endIndex
        let end = newText.index(newText.startIndex, offsetBy: result.selection.upperBound, limitedBy: newText.endIndex) ?? newText.endIndex
        textView.setSelectedRange(NSRange(start..<end, in: newText))
    }

    /// Insere as peças no cursor (no lugar da seleção): texto como veio e uma linha provisória por
    /// imagem, cada uma num bloco próprio.
    /// - Returns: o marcador de cada imagem, na ordem, com a fonte a gravar.
    func insert(_ pieces: [NoteImagePaste.Piece]) -> [(token: UUID, source: NoteImagePaste.Source)] {
        guard let textView else { return [] }
        let selected = textView.selectedRange()
        let text = textView.string as NSString
        let before = text.substring(to: selected.location)
        let after = text.substring(from: selected.location + selected.length)

        var built = ""
        var tokens: [(token: UUID, source: NoteImagePaste.Source)] = []
        var lastWasImage = false
        for piece in pieces {
            switch piece {
            case .text(let chunk):
                if lastWasImage {
                    built += "\n\n" + chunk.drop { $0 == "\n" }
                } else {
                    built += chunk
                }
                lastWasImage = false
            case .image(let source):
                let token = UUID()
                let preceding = before + built
                built += NoteImageMarkup.insertion(
                    of: [NoteImageMarkup.pendingLine(token: token)], after: preceding[...], before: "")
                tokens.append((token, source))
                lastWasImage = true
            }
        }
        if lastWasImage {
            let leading = after.prefix { $0 == "\n" }.count
            if !after.allSatisfy(\.isWhitespace) { built += String(repeating: "\n", count: max(0, 2 - leading)) }
        }

        let attributed = NSAttributedString(string: built, attributes: textView.typingAttributes)
        if textView.shouldChangeText(in: selected, replacementString: built) {
            textView.textStorage?.replaceCharacters(in: selected, with: attributed)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: selected.location + (built as NSString).length, length: 0))
            textView.scrollRangeToVisible(textView.selectedRange())
        }
        return tokens
    }

    /// O mesmo que `insert`, mas no fim do texto.
    func appendAtEnd(_ pieces: [NoteImagePaste.Piece]) -> [(token: UUID, source: NoteImagePaste.Source)] {
        guard let textView else { return [] }
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        return insert(pieces)
    }

    /// Troca a linha do marcador no texto vivo, desfazível.
    /// - Returns: `false` se o marcador não está mais no texto.
    func replacePending(_ token: UUID, with markdown: String) -> Bool {
        guard let textView,
            let newText = NoteImageMarkup.replacingPending(token, with: markdown, in: textView.string)
        else { return false }
        replaceString(with: newText, in: textView)
        return true
    }

    /// Troca só o trecho que mudou (entre o prefixo e o sufixo comuns), pelo caminho que registra o desfazer.
    private func replaceString(with newText: String, in textView: NSTextView) {
        let old = Array(textView.string.utf16)
        let new = Array(newText.utf16)
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
            old[old.count - 1 - suffix] == new[new.count - 1 - suffix]
        {
            suffix += 1
        }
        let range = NSRange(location: prefix, length: old.count - prefix - suffix)
        let replacement = String(decoding: new[prefix..<(new.count - suffix)], as: UTF16.self)
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        let attributed = NSAttributedString(string: replacement, attributes: textView.typingAttributes)
        textView.textStorage?.replaceCharacters(in: range, with: attributed)
        textView.didChangeText()
    }
}

/// `NSTextView` do corpo: aceita imagens ao colar e ao soltar, e conclui a edição com Esc.
class MarkdownSourceTextView: NSTextView {
    /// Chamado com as peças quando o colar ou soltar traz alguma imagem.
    var onPasteImages: (([NoteImagePaste.Piece]) -> Void)?
    var onEscape: (() -> Void)?
    var onFirstResponderChange: ((Bool) -> Void)?
    var onWindowChange: (() -> Void)?

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        var types = super.readablePasteboardTypes
        let extra: [NSPasteboard.PasteboardType] = [
            .fileURL, .png, .tiff, .rtfd, .init("com.apple.webarchive"), .init("public.jpeg"),
            .init("public.heic"), .init("com.compuserve.gif"),
        ]
        types += extra.filter { !types.contains($0) }
        return types
    }

    override func readSelection(from pboard: NSPasteboard) -> Bool {
        if pasteImages(from: pboard) { return true }
        return super.readSelection(from: pboard)
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if pasteImages(from: pboard) { return true }
        return super.readSelection(from: pboard, type: type)
    }

    private func pasteImages(from pasteboard: NSPasteboard) -> Bool {
        guard let onPasteImages, let pieces = NoteImagePaste.read(from: pasteboard) else { return false }
        onPasteImages(pieces)
        return true
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onFirstResponderChange?(true) }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { onFirstResponderChange?(false) }
        return result
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onWindowChange?() }
    }
}

/// Corpo da nota em Markdown: texto puro, monoespaçado, com ⌘V, Editar › Colar e soltar de imagens.
struct NoteBodyEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: NoteBodyEditorController
    let onImages: ([(token: UUID, source: NoteImagePaste.Source)]) -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = MarkdownSourceTextView(usingTextLayoutManager: true)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 0, height: 4)

        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.setAccessibilityLabel("Texto da nota em Markdown")

        let font = NSFont.monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        textView.font = font
        textView.textColor = .labelColor
        textView.defaultParagraphStyle = style
        textView.typingAttributes = [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: style]
        textView.string = text

        textView.delegate = context.coordinator
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        configure(textView, controller: controller)
        controller.attach(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? MarkdownSourceTextView else { return }
        configure(textView, controller: controller)
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            let location = min(selection.location, length)
            textView.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
        }
    }

    private func configure(_ textView: MarkdownSourceTextView, controller: NoteBodyEditorController) {
        textView.onEscape = onEscape
        textView.onPasteImages = { [controller, onImages] pieces in
            onImages(controller.insert(pieces))
        }
        textView.onFirstResponderChange = { [controller] value in controller.setFirstResponder(value) }
        textView.onWindowChange = { [controller] in controller.performPendingFocus() }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteBodyEditor

        init(_ parent: NoteBodyEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.text != textView.string { parent.text = textView.string }
        }
    }
}
