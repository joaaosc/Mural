import AppKit
import MuralKit
import SwiftUI
import Testing

@testable import Mural

@MainActor
@Suite("Ponte dos anexos do editor de texto")
struct EditorAttachmentBridgeTests {
    private struct Rig {
        let document: TextEditorDocument
        let bridge: EditorAttachmentBridge
        let textView: EditorTextView
        let window: NSWindow
    }

    private func makeRig() -> Rig {
        let document = TextEditorDocument()
        let bridge = EditorAttachmentBridge { [weak document] line in document?.content(forLine: line) }
        let scrollView = NSTextView.scrollableTextView()
        let textView = EditorTextView.make()
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        window.makeFirstResponder(textView)
        bridge.attach(textView)
        textView.bridge = bridge
        textView.onPaste = { [document] paste in document.paste(paste) }
        document.attach(bridge)
        return Rig(document: document, bridge: bridge, textView: textView, window: window)
    }

    /// Força o layout do campo, para os anexos pedirem o tamanho e criarem a view.
    private func layout(_ rig: Rig) {
        rig.textView.frame = NSRect(x: 0, y: 0, width: 480, height: 600)
        rig.textView.layoutSubtreeIfNeeded()
        if let manager = rig.textView.textLayoutManager {
            manager.ensureLayout(for: manager.documentRange)
        }
        rig.textView.layoutSubtreeIfNeeded()
    }

    private func png() -> Data {
        let image = NSImage(size: NSSize(width: 16, height: 8), flipped: false) { rect in
            NSColor.blue.setFill()
            rect.fill()
            return true
        }
        return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    }

    /// Um documento com dois cartões e uma imagem, com texto entre eles.
    private func fill(_ rig: Rig) {
        let document = rig.document
        document.embeds = [:]
        var text = "Começo.\n\n"
        for card in [
            EmbeddedCard.music(MusicSnapshot(kind: .album, title: "Abbey Road")),
            .contact(ContactSnapshot(givenName: "Fulana", familyName: "de Tal")),
        ] {
            let id = UUID()
            document.embeds[id] = card
            text += NoteImageMarkup.cardLine(id: id, title: card.title) + "\n\n"
        }
        let token = UUID()
        document.images[token] = .data(png(), fileExtension: "png")
        text += NoteImageMarkup.pendingLine(token: token) + "\n\nFim."
        document.text = text
        rig.bridge.reload(text)
    }

    private func attachments(in textView: NSTextView) -> [(range: NSRange, attachment: EmbeddedTextAttachment)] {
        var found: [(NSRange, EmbeddedTextAttachment)] = []
        guard let storage = textView.textStorage else { return [] }
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let attachment = value as? EmbeddedTextAttachment { found.append((range, attachment)) }
        }
        return found.map { (range: $0.0, attachment: $0.1) }
    }

    @Test("O Markdown vira um anexo por cartão e por imagem, e volta igual")
    func roundTrip() {
        let rig = makeRig()
        defer { rig.window.close() }
        fill(rig)
        #expect(attachments(in: rig.textView).count == 3)
        #expect(rig.bridge.markdown() == rig.document.text)
        #expect((rig.textView.string as NSString).length < rig.document.text.utf16.count, "cada linha de bloco é um caractere só")
    }

    @Test("Linha de bloco que o documento não sabe resolver fica como texto")
    func unresolvedLineStaysText() {
        let rig = makeRig()
        defer { rig.window.close() }
        let line = NoteImageMarkup.cardLine(id: UUID(), title: "Sumiu")
        rig.bridge.reload("antes\n\n\(line)\n\ndepois")
        #expect(attachments(in: rig.textView).isEmpty)
        #expect(rig.bridge.markdown() == "antes\n\n\(line)\n\ndepois")
    }

    @Test("O campo usa TextKit 2")
    func usesTextKit2() {
        let rig = makeRig()
        defer { rig.window.close() }
        #expect(rig.textView.textLayoutManager != nil)
    }

    @Test("Apagar o caractere do anexo tira a linha do Markdown; o ⌘Z a devolve")
    func deleteAndUndo() throws {
        let rig = makeRig()
        defer { rig.window.close() }
        fill(rig)
        let before = rig.bridge.markdown()
        let first = try #require(attachments(in: rig.textView).first)
        let undo = try #require(rig.textView.undoManager)
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        #expect(rig.textView.shouldChangeText(in: first.range, replacementString: ""))
        rig.textView.textStorage?.replaceCharacters(in: first.range, with: "")
        rig.textView.didChangeText()
        undo.endUndoGrouping()

        #expect(!rig.bridge.markdown().contains(first.attachment.markdownLine))
        #expect(attachments(in: rig.textView).count == 2)

        undo.undo()
        #expect(rig.bridge.markdown() == before)
        #expect(attachments(in: rig.textView).count == 3)
    }

    @Test("Inserir um cartão no cursor passa pelo campo, desfaz com ⌘Z e atualiza o documento")
    func insertThroughTheField() throws {
        let rig = makeRig()
        defer { rig.window.close() }
        rig.bridge.reload("um texto")
        rig.textView.setSelectedRange(NSRange(location: 2, length: 0))
        let undo = try #require(rig.textView.undoManager)
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        rig.document.insertCards([.contact(ContactSnapshot(givenName: "Ana"))])
        undo.endUndoGrouping()

        #expect(attachments(in: rig.textView).count == 1)
        #expect(rig.bridge.markdown().hasPrefix("um\n\n![Ana](mural-card:"))
        rig.document.sync(markdown: rig.bridge.markdown(), selectionUTF16: rig.bridge.markdownSelection())
        #expect(rig.document.text == rig.bridge.markdown())

        undo.undo()
        #expect(rig.bridge.markdown() == "um texto")
    }

    @Test("A seleção do campo vira uma seleção no Markdown, e a formatação mexe só nela")
    func selectionMapsToMarkdown() throws {
        let rig = makeRig()
        defer { rig.window.close() }
        rig.bridge.reload("ola mundo")
        rig.textView.setSelectedRange(NSRange(location: 4, length: 5))
        let range = try #require(rig.bridge.markdownSelection())
        rig.document.sync(markdown: rig.bridge.markdown(), selectionUTF16: range)
        #expect(rig.document.text[try #require(rig.document.selection)] == "mundo")

        rig.document.applyFormat(.uppercase, locale: Locale(identifier: "pt_BR"))
        #expect(rig.bridge.markdown() == "ola MUNDO")
        #expect(rig.textView.selectedRange() == NSRange(location: 4, length: 5))
    }

    // MARK: Bordas

    @Test("Digitar logo depois de um anexo deixa uma linha em branco entre o cartão e o texto")
    func typingRightAfterAnAttachment() throws {
        let rig = makeRig()
        defer { rig.window.close() }
        fill(rig)
        let last = try #require(attachments(in: rig.textView).last)
        rig.textView.setSelectedRange(NSRange(location: last.range.upperBound, length: 0))
        rig.textView.insertText("abc", replacementRange: rig.textView.selectedRange())
        let markdown = rig.bridge.markdown()
        #expect(markdown.contains("\(last.attachment.markdownLine)\n\nabc"))
    }

    @Test("Dois anexos em seguida, no começo e no fim, voltam como blocos separados")
    func adjacentAndEdgeAttachments() throws {
        let rig = makeRig()
        defer { rig.window.close() }
        var lines: [String] = []
        for title in ["Um", "Dois"] {
            let id = UUID()
            rig.document.embeds[id] = .contact(ContactSnapshot(givenName: title))
            lines.append(NoteImageMarkup.cardLine(id: id, title: title))
        }
        rig.bridge.reload(lines.joined(separator: "\n\n"))
        #expect(attachments(in: rig.textView).count == 2)
        #expect(rig.bridge.markdown() == lines.joined(separator: "\n\n"))
        // Dois anexos grudados (sem quebra entre eles) também viram dois blocos.
        let storage = try #require(rig.textView.textStorage)
        let second = try #require(attachments(in: rig.textView).last)
        storage.replaceCharacters(in: NSRange(location: second.range.location - 2, length: 2), with: "")
        #expect(rig.bridge.markdown() == lines.joined(separator: "\n\n"))
    }

    @Test("A seleção em texto com emoji (pares substitutos UTF-16) cai nos caracteres certos")
    func selectionWithEmoji() throws {
        let rig = makeRig()
        defer { rig.window.close() }
        rig.bridge.reload("😀 ola mundo")
        rig.textView.setSelectedRange(NSRange(location: 3, length: 3))
        rig.document.sync(markdown: rig.bridge.markdown(), selectionUTF16: rig.bridge.markdownSelection())
        #expect(rig.document.text[try #require(rig.document.selection)] == "ola")
    }

    @Test("Copiar leva o Markdown do anexo e colar de volta, depois de apagá-lo, refaz o anexo")
    func cutAndPasteAnAttachment() throws {
        let rig = makeRig()
        defer { rig.window.close() }
        fill(rig)
        let first = try #require(attachments(in: rig.textView).first)
        rig.textView.setSelectedRange(first.range)
        let pasteboard = NSPasteboard(name: .init("mural-editor-ponte-\(UUID().uuidString)"))
        pasteboard.clearContents()
        #expect(rig.textView.writablePasteboardTypes == [.string])
        #expect(rig.textView.writeSelection(to: pasteboard, type: .string))
        #expect(pasteboard.string(forType: .string) == first.attachment.markdownLine)

        rig.textView.shouldChangeText(in: first.range, replacementString: "")
        rig.textView.textStorage?.replaceCharacters(in: first.range, with: "")
        rig.textView.didChangeText()
        #expect(attachments(in: rig.textView).count == 2)

        rig.textView.setSelectedRange(NSRange(location: first.range.location, length: 0))
        #expect(rig.textView.readSelection(from: pasteboard, type: .string))
        #expect(attachments(in: rig.textView).count == 3)
    }

    @Test("Colar uma linha de cartão de outro documento deixa texto, não anexo")
    func unknownCardLineStaysText() {
        let rig = makeRig()
        defer { rig.window.close() }
        let line = NoteImageMarkup.cardLine(id: UUID(), title: "Outro")
        let pasteboard = NSPasteboard(name: .init("mural-editor-ponte-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString(line, forType: .string)
        #expect(rig.textView.readSelection(from: pasteboard, type: .string))
        #expect(attachments(in: rig.textView).isEmpty)
        #expect(rig.bridge.markdown().contains("mural-card:"))
    }

    @Test("As Ferramentas de Escrita ignoram os anexos, e o desfazer é do coordenador")
    func writingToolsRangesAndOwnUndo() {
        let rig = makeRig()
        defer { rig.window.close() }
        fill(rig)
        let coordinator = TextEditorBody.Coordinator(document: rig.document)
        coordinator.install(in: rig.textView)
        let whole = NSRange(location: 0, length: rig.textView.textStorage?.length ?? 0)
        let ignored = coordinator.textView(rig.textView, writingToolsIgnoredRangesInEnclosingRange: whole)
        #expect(ignored.count == 3 && ignored.allSatisfy { $0.rangeValue.length == 1 })
        #expect(coordinator.undoManager(for: rig.textView) === coordinator.undoManager(for: rig.textView))
        #expect(coordinator.undoManager(for: rig.textView) !== rig.window.undoManager)
    }

    @Test("No layout os anexos pedem o tamanho e criam a view, com no máximo 320 pt")
    func layoutCreatesTheAttachmentViews() throws {
        let rig = makeRig()
        defer { rig.window.close() }
        fill(rig)
        layout(rig)
        let attachment = try #require(attachments(in: rig.textView).first?.attachment)
        let bounds = attachment.attachmentBounds(
            for: [:], location: rig.textView.textLayoutManager!.documentRange.location, textContainer: rig.textView.textContainer,
            proposedLineFragment: CGRect(x: 0, y: 0, width: 480, height: 20), position: .zero)
        #expect(bounds.width <= 320 && bounds.width > 0 && bounds.height > 0)
        let provider = try #require(
            attachment.viewProvider(
                for: rig.textView, location: rig.textView.textLayoutManager!.documentRange.location,
                textContainer: rig.textView.textContainer))
        provider.loadView()
        #expect(provider.view is NSHostingView<EmbeddedCardScaledContent>)
    }
}
