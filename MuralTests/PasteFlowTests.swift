import AppKit
import Foundation
import MuralKit
import Testing

@testable import Mural

@MainActor
@Suite("Colar e copiar texto")
struct PasteFlowTests {
    /// Área de transferência própria do teste, para não mexer na do usuário.
    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("MuralTests-\(UUID().uuidString)"))
    }

    @Test("Texto solto chega como texto, para o popup escolher o tipo")
    func textWaitsForChoice() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("Ligar para o marceneiro", forType: .string)
        guard case .text(let text) = PasteboardImporter.read(from: pasteboard) else {
            Issue.record("Texto solto deveria chegar como .text")
            return
        }
        #expect(text == "Ligar para o marceneiro")
    }

    @Test("Só espaços não chega como texto, então não abre o popup")
    func blankTextIsNothing() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("  \n ", forType: .string)
        guard case .nothing = PasteboardImporter.read(from: pasteboard) else {
            Issue.record("Texto só com espaços deveria ser .nothing")
            return
        }
    }

    @Test("Imagem continua sendo lida como dados, para virar cartão na hora")
    func imageIsReadAsData() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        guard case .data(_, let fileExtension, let kind, _) = PasteboardImporter.read(from: pasteboard) else {
            Issue.record("Imagem PNG deveria ser lida como dados")
            return
        }
        #expect(fileExtension == "png")
        #expect(kind == .image)
    }

    @Test("Popup: a sugestão e as opções vêm do texto; a pasta aberta é guardada")
    func pendingPaste() {
        let folder = UUID()
        let list = PendingPaste(text: "Compras\n- pão\n- leite", folderID: folder)
        #expect(list.choice.suggested == .checklist)
        #expect(list.choice.options == [.sticky, .text, .checklist])
        #expect(list.folderID == folder)
        let long = PendingPaste(text: String(repeating: "palavra ", count: 80), folderID: nil)
        #expect(long.choice.options == [.sticky, .text])
        #expect(long.preview.count == 401)
        #expect(long.preview.hasSuffix("…"))
    }

    @Test("Nota copiada leva o título como `#` e volta igual ao colar")
    func copiedNoteRoundTrips() throws {
        let note = BoardItem(kind: .text, title: "Visita", text: "Corpo da nota. Com duas frases.")
        let markdown = PasteboardExporter.markdown(of: note)
        #expect(markdown == "# Visita\n\nCorpo da nota. Com duas frases.")
        let pasted = try ItemImporter(itemsDirectory: FileManager.default.temporaryDirectory).importText(markdown, as: .text)
        #expect(pasted.title == note.title)
        #expect(pasted.text == note.text)

        // Título que já é a primeira linha do corpo, ou corpo com `#`, não ganha outro título.
        let plain = BoardItem(kind: .text, title: "Comprar tinta", text: "Comprar tinta\nazul e branca")
        #expect(PasteboardExporter.markdown(of: plain) == "Comprar tinta\nazul e branca")
        let heading = BoardItem(kind: .text, title: "Outro", text: "# Já tem\ncorpo")
        #expect(PasteboardExporter.markdown(of: heading) == "# Já tem\ncorpo")
        #expect(PasteboardExporter.markdown(of: BoardItem(kind: .text, title: "Só título")) == "# Só título")
    }
}
