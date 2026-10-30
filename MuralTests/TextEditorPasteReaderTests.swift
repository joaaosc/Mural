import AppKit
import Foundation
import MuralKit
import Testing

@testable import Mural

@MainActor
@Suite("Leitor de colagem do editor de texto")
struct TextEditorPasteReaderTests {
    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("mural-editor-teste-\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }

    private let vCard = "BEGIN:VCARD\nVERSION:3.0\nN:Tal;Fulana;;;\nFN:Fulana Tal\nEND:VCARD\n"

    private func pngData() throws -> Data {
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        return try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    }

    @Test("Nada na área de transferência")
    func nothing() {
        guard case .nothing = TextEditorPasteReader.read(from: makePasteboard()) else {
            Issue.record("esperava .nothing")
            return
        }
    }

    @Test("vCard vira contatos e vale mais que o texto que vem junto")
    func vCardComesFirst() {
        let pasteboard = makePasteboard()
        pasteboard.setData(Data(vCard.utf8), forType: ContactVCardReader.vCardType)
        pasteboard.setString("Fulana Tal", forType: .string)
        guard case .contacts(let drafts) = TextEditorPasteReader.read(from: pasteboard) else {
            Issue.record("esperava .contacts")
            return
        }
        #expect(drafts.first?.snapshot.displayName == "Fulana Tal")
    }

    @Test("Link do Apple Music vira música")
    func music() {
        let pasteboard = makePasteboard()
        pasteboard.setString("https://music.apple.com/br/album/abbey-road/1441164426", forType: .string)
        guard case .music(let drafts) = TextEditorPasteReader.read(from: pasteboard) else {
            Issue.record("esperava .music")
            return
        }
        #expect(drafts.count == 1)
    }

    @Test("Texto que é só endereços vira links; um parágrafo com um link continua texto")
    func linksOnlyWhenTheTextIsOnlyAddresses() {
        let only = makePasteboard()
        only.setString("https://example.com/a\nhttps://example.com/b", forType: .string)
        guard case .links(let drafts) = TextEditorPasteReader.read(from: only) else {
            Issue.record("esperava .links")
            return
        }
        #expect(drafts.count == 2)

        let paragraph = makePasteboard()
        paragraph.setString("Veja https://example.com/a para detalhes.", forType: .string)
        guard case .text(let text) = TextEditorPasteReader.read(from: paragraph) else {
            Issue.record("esperava .text")
            return
        }
        #expect(text.hasPrefix("Veja"))
    }

    @Test("Dados de imagem viram imagens e texto simples vira texto")
    func imagesAndText() throws {
        let image = makePasteboard()
        image.setData(try pngData(), forType: .png)
        guard case .images(let pieces) = TextEditorPasteReader.read(from: image), pieces.count == 1 else {
            Issue.record("esperava .images")
            return
        }

        let plain = makePasteboard()
        plain.setString("só texto", forType: .string)
        guard case .text(let text) = TextEditorPasteReader.read(from: plain) else {
            Issue.record("esperava .text")
            return
        }
        #expect(text == "só texto")
    }

    @Test("Cada tipo vira o cartão embutido certo, sem foto de contato nem capa de música")
    func mapsToEmbeddedCards() {
        let contact = ContactDraft(
            snapshot: ContactSnapshot(givenName: "Ana", thumbnailFile: "foto.png"), thumbnailData: Data([1]))
        let music = MusicDraft(snapshot: MusicSnapshot(kind: .song, title: "Faixa", artworkFile: "capa.jpg"), artworkData: Data([1]))
        let link = LinkDraft(url: URL(string: "https://example.com")!, title: "Exemplo")
        #expect(TextEditorPaste.contacts([contact]).embeddedCards == [.contact(contact.snapshot)])
        #expect(TextEditorPaste.music([music]).embeddedCards == [.music(music.snapshot)])
        guard case .link(let info)? = TextEditorPaste.links([link]).embeddedCards.first else {
            Issue.record("esperava .link")
            return
        }
        #expect(info.url == link.url && info.pageTitle == "Exemplo" && info.preview == .pending)
        #expect(TextEditorPaste.text("x").embeddedCards.isEmpty && TextEditorPaste.nothing.embeddedCards.isEmpty)
    }

    @Test("Parágrafo com um link continua texto mesmo com os tipos de link do Safari na área de transferência")
    func paragraphWinsOverSafariLinkTypes() {
        let pasteboard = makePasteboard()
        pasteboard.setString("Veja https://example.com/a para detalhes.", forType: .string)
        pasteboard.setPropertyList(
            [["https://example.com/a"], ["Exemplo"]], forType: NSPasteboard.PasteboardType("WebURLsWithTitlesPboardType"))
        guard case .text = TextEditorPasteReader.read(from: pasteboard) else {
            Issue.record("esperava .text")
            return
        }
    }
}
