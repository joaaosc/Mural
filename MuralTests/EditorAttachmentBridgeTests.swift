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

    @Test("O anexo tem no máximo 320 pt, é desenhado como imagem e nunca como view")
    func attachmentIsDrawnAsAnImage() throws {
        let rig = makeRig()
        defer { rig.window.close() }
        fill(rig)
        layout(rig)
        let attachment = try #require(attachments(in: rig.textView).first?.attachment)
        let location = try #require(rig.textView.textLayoutManager?.documentRange.location)
        let bounds = attachment.attachmentBounds(
            for: [:], location: location, textContainer: rig.textView.textContainer,
            proposedLineFragment: CGRect(x: 0, y: 0, width: 480, height: 20), position: .zero)
        #expect(bounds.width == EmbeddedCardStrip.maximumWidth && bounds.height == EmbeddedCardStrip.height)
        #expect(attachment.viewProvider(for: rig.textView, location: location, textContainer: rig.textView.textContainer) == nil)
        #expect(!attachment.allowsTextAttachmentView)
        let image = attachment.image(for: bounds, attributes: [:], location: location, textContainer: rig.textView.textContainer)
        #expect(image?.size == bounds.size)
        #expect(image?.accessibilityDescription == "Música, Abbey Road")
    }

    @Test("O anexo escolhe o desenho pela aparência do campo")
    func attachmentFollowsTheAppearance() throws {
        let rig = makeRig()
        defer { rig.window.close() }
        fill(rig)
        let attachment = try #require(attachments(in: rig.textView).first?.attachment)
        let location = try #require(rig.textView.textLayoutManager?.documentRange.location)
        func drawn() -> NSImage? {
            attachment.image(for: .zero, attributes: [:], location: location, textContainer: rig.textView.textContainer)
        }
        rig.textView.appearance = NSAppearance(named: .aqua)
        #expect(drawn() === attachment.picture?.light)
        rig.textView.appearance = NSAppearance(named: .darkAqua)
        #expect(drawn() === attachment.picture?.dark)
    }

    @Test("Recarregar o texto não desenha o anexo de novo")
    func picturesAreReusedAcrossReloads() throws {
        let rig = makeRig()
        defer { rig.window.close() }
        fill(rig)
        let before = try #require(attachments(in: rig.textView).first?.attachment.picture?.light)
        rig.bridge.reload(rig.document.text)
        #expect(attachments(in: rig.textView).first?.attachment.picture?.light === before)
    }

    @Test("O desenho do anexo já vem pronto com o conteúdo da imagem colada, sem esperar a tela")
    func pictureHoldsThePastedImage() throws {
        let rig = makeRig()
        defer { rig.window.close() }
        rig.document.insertImages([.data(png(), fileExtension: "png")])
        let picture = try #require(attachments(in: rig.textView).first?.attachment.picture?.light)
        var rect = CGRect(origin: .zero, size: picture.size)
        let image = try #require(picture.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        #expect(picture.size == CGSize(width: 320, height: 160))
        #expect(image.width == 640, "o dobro dos pontos, para ficar nítido nas telas Retina")
        let center = try #require(NSBitmapImageRep(cgImage: image).colorAt(x: image.width / 2, y: image.height / 2))
        #expect(center.blueComponent > 0.8 && center.redComponent < 0.3 && center.alphaComponent > 0.9)
    }

    @Test("Colar no fim deixa uma linha livre e o cursor nela; as setas passam por cima do anexo")
    func cursorJumpsOverTheAttachment() throws {
        let rig = makeRig()
        defer { rig.window.close() }
        let coordinator = TextEditorBody.Coordinator(document: rig.document)
        coordinator.install(in: rig.textView)
        rig.textView.delegate = coordinator
        rig.textView.insertText("eeee", replacementRange: rig.textView.selectedRange())
        rig.document.insertCards([.contact(ContactSnapshot(givenName: "Ana"))])
        // "eeee", duas quebras, o anexo e a quebra da linha livre.
        #expect(rig.textView.string == "eeee\n\n\u{FFFC}\n")
        #expect(rig.textView.selectedRange() == NSRange(location: 8, length: 0))

        rig.textView.moveUp(nil)
        #expect(rig.textView.selectedRange().location == 5, "sobe para a linha em branco de antes do anexo")
        rig.textView.moveDown(nil)
        #expect(rig.textView.selectedRange().location == 8, "desce para a linha livre de depois dele")
        rig.textView.moveLeft(nil)
        #expect(rig.textView.selectedRange().location == 5)
        rig.textView.moveRight(nil)
        #expect(rig.textView.selectedRange().location == 8)
    }

    @Test("Selecionar um trecho que tem o anexo continua possível")
    func rangeSelectionIsNotTouched() throws {
        let rig = makeRig()
        defer { rig.window.close() }
        let coordinator = TextEditorBody.Coordinator(document: rig.document)
        coordinator.install(in: rig.textView)
        rig.textView.delegate = coordinator
        fill(rig)
        let first = try #require(attachments(in: rig.textView).first)
        rig.textView.setSelectedRange(first.range)
        #expect(rig.textView.selectedRange() == first.range)
    }

    @Test("⌫ logo abaixo do anexo e Delete logo acima apagam o bloco, e o ⌘Z o devolve")
    func deletingAroundAnAttachment() throws {
        let rig = makeRig()
        defer { rig.window.close() }
        let coordinator = TextEditorBody.Coordinator(document: rig.document)
        coordinator.install(in: rig.textView)
        rig.textView.delegate = coordinator
        let id = UUID()
        rig.document.embeds[id] = .contact(ContactSnapshot(givenName: "Ana"))
        let line = NoteImageMarkup.cardLine(id: id, title: "Ana")
        let text = "um\n\(line)\ndois"
        rig.document.text = text
        rig.bridge.reload(text)
        let undo = try #require(coordinator.undoManager(for: rig.textView))
        undo.groupsByEvent = false

        rig.textView.setSelectedRange(NSRange(location: 5, length: 0))
        undo.beginUndoGrouping()
        rig.textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        undo.endUndoGrouping()
        #expect(rig.bridge.markdown() == "um\ndois")
        undo.undo()
        #expect(rig.bridge.markdown() == text)

        rig.textView.setSelectedRange(NSRange(location: 2, length: 0))
        undo.beginUndoGrouping()
        rig.textView.doCommand(by: #selector(NSResponder.deleteForward(_:)))
        undo.endUndoGrouping()
        #expect(rig.bridge.markdown() == "um\ndois")

        // Longe de um anexo, o ⌫ é o de sempre.
        rig.textView.setSelectedRange(NSRange(location: 2, length: 0))
        undo.beginUndoGrouping()
        rig.textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        undo.endUndoGrouping()
        #expect(rig.bridge.markdown() == "u\ndois")
    }

    @Test("A linha livre do fim não vai para o mural")
    func deliverableTextDropsTheFreeLine() {
        let rig = makeRig()
        defer { rig.window.close() }
        rig.document.insertCards([.contact(ContactSnapshot(givenName: "Ana"))])
        rig.document.sync(markdown: rig.bridge.markdown(), selectionUTF16: rig.bridge.markdownSelection())
        #expect(rig.document.text.hasSuffix("\n"))
        #expect(!rig.document.deliverableText.hasSuffix("\n"))
    }
}

/// A regra do cursor em volta dos anexos, sem campo: ▣ é o anexo.
@Suite("Cursor em volta dos anexos")
struct EditorCaretTests {
    private func text(_ string: String) -> NSString {
        string.replacingOccurrences(of: "▣", with: "\u{FFFC}") as NSString
    }

    @Test("Posição longe de um anexo fica como está")
    func farFromAnAttachment() {
        #expect(EditorCaret.location(for: 2, movingForward: true, in: text("abcd\n▣\n")) == 2)
        #expect(EditorCaret.location(for: 5, movingForward: false, in: text("abcd\n\n▣")) == 5)
    }

    @Test("Colada a um anexo, a posição vai para a linha seguinte ou a anterior, conforme o movimento")
    func jumpsOverTheAttachment() {
        let string = text("ab\n▣\ncd")
        for proposed in [3, 4] {
            #expect(EditorCaret.location(for: proposed, movingForward: true, in: string) == 5)
            #expect(EditorCaret.location(for: proposed, movingForward: false, in: string) == 2)
        }
    }

    @Test("Passa por dois anexos seguidos")
    func jumpsOverTwoAttachments() {
        let string = text("a\n▣\n▣\nb")
        #expect(EditorCaret.location(for: 2, movingForward: true, in: string) == 6)
        #expect(EditorCaret.location(for: 5, movingForward: false, in: string) == 1)
    }

    @Test("No começo do texto o cursor pode ficar antes do anexo; depois dele, sem linha, fica colado")
    func edges() {
        #expect(EditorCaret.location(for: 0, movingForward: true, in: text("▣\nab")) == 0)
        #expect(EditorCaret.location(for: 1, movingForward: false, in: text("▣\nab")) == 0)
        #expect(EditorCaret.location(for: 1, movingForward: true, in: text("▣\nab")) == 2)
        #expect(EditorCaret.location(for: 3, movingForward: true, in: text("ab\n▣")) == 4)
        #expect(EditorCaret.location(for: 4, movingForward: true, in: text("ab\n▣")) == 4)
    }

    @Test("Texto vazio não quebra a regra")
    func emptyText() {
        #expect(EditorCaret.location(for: 0, movingForward: true, in: "") == 0)
        #expect(EditorCaret.rangeDeletedBackward(from: 0, in: "") == nil)
        #expect(EditorCaret.rangeDeletedForward(from: 0, in: "") == nil)
    }

    @Test("⌫ apaga o anexo e a quebra só no começo da linha logo abaixo dele")
    func deleteBackward() {
        #expect(EditorCaret.rangeDeletedBackward(from: 4, in: text("a\n▣\nb")) == NSRange(location: 2, length: 2))
        #expect(EditorCaret.rangeDeletedBackward(from: 5, in: text("a\n▣\n\nb")) == nil)
        #expect(EditorCaret.rangeDeletedBackward(from: 1, in: text("a\n▣\nb")) == nil)
    }

    @Test("Delete apaga o anexo e a quebra só no fim da linha logo acima dele")
    func deleteForward() {
        #expect(EditorCaret.rangeDeletedForward(from: 1, in: text("a\n▣\nb")) == NSRange(location: 2, length: 2))
        #expect(EditorCaret.rangeDeletedForward(from: 1, in: text("a\n▣")) == NSRange(location: 2, length: 1))
        #expect(EditorCaret.rangeDeletedForward(from: 0, in: text("a\n▣\nb")) == nil)
    }
}
