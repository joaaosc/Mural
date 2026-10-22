import AppKit
import Foundation
import MuralKit
import Testing

@testable import Mural

@Suite("Texto formatado para o Notas")
@MainActor
struct NotesSharingTests {
    private func render(_ blocks: [NoteExport.Block], imageURL: @escaping (String) -> URL? = { _ in nil })
        -> NSAttributedString
    {
        NotesRichText.attributedString(for: blocks, imageURL: imageURL)
    }

    private func isBold(_ text: NSAttributedString, at index: Int) -> Bool {
        let font = text.attribute(.font, at: index, effectiveRange: nil) as? NSFont
        return font?.fontDescriptor.symbolicTraits.contains(.bold) == true
    }

    @Test("começa pelo título em negrito")
    func titleFirst() {
        let text = render([.title("Ideias"), .paragraph("corpo")])
        #expect(text.string == "Ideias\ncorpo")
        #expect(isBold(text, at: 0))
        #expect(!isBold(text, at: 8))
    }

    @Test("**x** vira negrito")
    func inlineBold() {
        let text = render([.paragraph("um **forte** dia")])
        #expect(text.string == "um forte dia")
        #expect(isBold(text, at: 4))
        #expect(!isBold(text, at: 0))
    }

    @Test("tarefa feita começa com ☑ e a aberta com ☐")
    func tasks() {
        let text = render([
            .listItem(marker: .task(done: true), depth: 0, text: "feito"),
            .listItem(marker: .task(done: false), depth: 0, text: "aberto"),
        ])
        #expect(text.string == "☑ feito\n☐ aberto")
    }

    @Test("imagem com arquivo vira anexo")
    func imageWithFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let text = render([.image(fileName: "x.png", alt: "Foto")]) { _ in url }
        #expect(text.attribute(.attachment, at: 0, effectiveRange: nil) is NSTextAttachment)
        #expect(!text.string.contains("Foto"))
    }

    @Test("imagem sem arquivo vira o texto alternativo")
    func imageWithoutFile() {
        let text = render([.image(fileName: "x.png", alt: "Foto")])
        #expect(text.string == "Foto")
    }

    @Test("post-it sai como o texto")
    func sticky() {
        let item = BoardItem(kind: .sticky, title: "T", text: "Comprar pão")
        #expect(render(NoteExport.blocks(for: item)).string == "Comprar pão")
    }
}
