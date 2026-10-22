import AppKit
import MuralKit
import Testing

@testable import Mural

@MainActor
struct NoteBodyEditorTests {
    /// Texto do corpo dentro de uma janela fora da tela, para ter o gerenciador de desfazer.
    private func makeEditor(text: String = "") -> (MarkdownSourceTextView, NoteBodyEditorController, NSWindow) {
        let textView = MarkdownSourceTextView(usingTextLayoutManager: true)
        textView.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.string = text
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 300, height: 200), styleMask: [.titled],
            backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = textView
        let controller = NoteBodyEditorController()
        controller.attach(textView)
        return (textView, controller, window)
    }

    private func privatePasteboard() -> NSPasteboard {
        NSPasteboard(name: .init("mural-teste-\(UUID().uuidString)"))
    }

    @Test func pastingPNGInsertsPendingLineAndReportsSource() throws {
        let (textView, controller, _) = makeEditor(text: "antes")
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        var received: [(token: UUID, source: NoteImagePaste.Source)] = []
        textView.onPasteImages = { received = controller.insert($0) }
        let pasteboard = privatePasteboard()
        pasteboard.clearContents()
        pasteboard.setData(try TestImage.png(width: 8, height: 8), forType: .png)

        #expect(textView.readSelection(from: pasteboard))
        #expect(received.count == 1)
        let token = try #require(received.first?.token)
        #expect(textView.string == "antes\n\n" + NoteImageMarkup.pendingLine(token: token))
    }

    @Test func pastingOnlyTextPastesNormally() {
        let (textView, controller, _) = makeEditor()
        var called = false
        textView.onPasteImages = { pieces in
            called = true
            _ = controller.insert(pieces)
        }
        let pasteboard = privatePasteboard()
        pasteboard.clearContents()
        pasteboard.setString("só texto", forType: .string)

        #expect(textView.readSelection(from: pasteboard, type: .string))
        #expect(!called)
        #expect(textView.string == "só texto")
    }

    @Test func toggleBoldWrapsSelectionAndUndoRestores() throws {
        let (textView, controller, _) = makeEditor(text: "olá mundo")
        textView.setSelectedRange(NSRange(location: 4, length: 5))

        controller.toggle(.bold)
        #expect(textView.string == "olá **mundo**")
        #expect(textView.selectedRange() == NSRange(location: 6, length: 5))

        try #require(textView.undoManager).undo()
        #expect(textView.string == "olá mundo")
    }

    @Test func replacePendingSwapsMarkerAndMissingTokenFails() {
        let (textView, controller, _) = makeEditor()
        let token = UUID()
        textView.string = "a\n\n" + NoteImageMarkup.pendingLine(token: token) + "\n\nb"

        #expect(controller.replacePending(token, with: "![x](f.png)"))
        #expect(textView.string == "a\n\n![x](f.png)\n\nb")
        #expect(!controller.replacePending(UUID(), with: "![x](f.png)"))
    }

    @Test func appendAtEndSeparatesImageWithBlankLine() throws {
        let (textView, controller, _) = makeEditor(text: "texto")
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        let tokens = controller.appendAtEnd([.image(.data(try TestImage.png(width: 4, height: 4), fileExtension: "png"))])

        let token = try #require(tokens.first?.token)
        #expect(textView.string == "texto\n\n" + NoteImageMarkup.pendingLine(token: token))
    }

    @Test func cancelOperationCallsOnEscape() {
        let (textView, _, _) = makeEditor()
        var escaped = false
        textView.onEscape = { escaped = true }
        textView.cancelOperation(nil)
        #expect(escaped)
    }
}
