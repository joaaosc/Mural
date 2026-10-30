import AppKit
import Foundation
import MuralKit
import Testing
import UniformTypeIdentifiers

@testable import Mural

/// O botão Inserir do editor: os itens do menu e a leitura dos arquivos escolhidos no Finder.
@MainActor
@Suite("Inserir no editor de texto")
struct TextEditorInsertionTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("EditorInserir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func png() -> Data {
        let image = NSImage(size: NSSize(width: 16, height: 8), flipped: false) { rect in
            NSColor.blue.setFill()
            rect.fill()
            return true
        }
        return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    }

    private let vCard = Data("BEGIN:VCARD\nVERSION:3.0\nN:de Tal;Fulana;;;\nFN:Fulana de Tal\nEND:VCARD\n".utf8)

    @Test("O menu tem as fotos, um item por tipo de cartão embutido e o Finder por último, cada um com um SF Symbol próprio")
    func menuItems() {
        let items = TextEditorInsertion.allCases
        #expect(items == [.photos, .music, .reminder, .link, .contact, .finder])
        #expect(Set(items.map(\.symbolName)).count == items.count)
        #expect(items.allSatisfy { $0.title.hasSuffix("…") })
        #expect(items.filter(\.usesSheet) == [.music, .reminder, .link])
    }

    @Test("O painel do Finder só deixa escolher imagens e contatos")
    func allowedTypes() {
        #expect(TextEditorFileInsertion.allowedTypes.contains(.image) && TextEditorFileInsertion.allowedTypes.contains(.vCard))
        #expect(TextEditorFileInsertion.allowedTypes.count == 2)
        #expect(!TextEditorFileInsertion.allowedTypes.contains { UTType.pdf.conforms(to: $0) })
        #expect(!TextEditorFileInsertion.allowedTypes.contains { UTType.plainText.conforms(to: $0) })
        #expect(!TextEditorFileInsertion.allowedTypes.contains { UTType.mpeg4Movie.conforms(to: $0) })
        #expect(TextEditorFileInsertion.contactTypes == [.vCard])
    }

    @Test("Imagem e vCard entram na ordem dos arquivos; o resto é contado como falha e não impede os outros")
    func readsFilesInOrder() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appendingPathComponent("foto.png")
        let contact = folder.appendingPathComponent("fulana.vcf")
        let broken = folder.appendingPathComponent("quebrada.jpg")
        let empty = folder.appendingPathComponent("vazia.png")
        try png().write(to: image)
        try vCard.write(to: contact)
        try Data("isto não é uma imagem".utf8).write(to: broken)
        try Data().write(to: empty)
        let missing = folder.appendingPathComponent("sumiu.png")

        let reading = await TextEditorFileInsertion.read([contact, broken, image, empty, missing])

        #expect(reading.failures == 3)
        #expect(reading.pieces.count == 2)
        guard case .contacts(let drafts) = reading.pieces[0], case .image(.data(let data, let fileExtension)) = reading.pieces[1] else {
            Issue.record("as peças deveriam vir na ordem dos arquivos: \(reading.pieces)")
            return
        }
        #expect(drafts.first?.snapshot.displayName == "Fulana de Tal")
        #expect(data == (try Data(contentsOf: image)) && fileExtension == "png")
    }

    @Test("Um vCard sem contato legível é uma falha")
    func unreadableContact() async throws {
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("ruim.vcf")
        try Data("isto não é um vCard".utf8).write(to: file)
        let reading = await TextEditorFileInsertion.read([file])
        #expect(reading.pieces.isEmpty && reading.failures == 1)
    }

    @Test("A imagem nos formatos do anexo vai como veio; nos outros, para converter em PNG")
    func imageSource() {
        let data = Data([1, 2, 3])
        guard case .data(_, "jpg") = NoteImagePaste.source(data: data, fileExtension: "JPEG") else {
            Issue.record("JPEG deveria ir como jpg")
            return
        }
        guard case .data(_, "heic") = NoteImagePaste.source(data: data, fileExtension: "heic") else {
            Issue.record("HEIC deveria ir como veio")
            return
        }
        guard case .needsPNGConversion = NoteImagePaste.source(data: data, fileExtension: "webp") else {
            Issue.record("WebP deveria ser convertido")
            return
        }
    }

    @Test("O que veio dos arquivos entra no documento como imagem e cartão de contato")
    func documentInsertsPieces() throws {
        let document = TextEditorDocument()
        let draft = ContactDraft(snapshot: ContactSnapshot(givenName: "Ana"), thumbnailData: nil)
        document.insert([.image(.data(png(), fileExtension: "png")), .contacts([draft])])
        #expect(document.images.count == 1 && document.embeds.count == 1)
        #expect(document.hasImages && document.hasEmbeds)
    }

    @Test("A busca de música filtra o catálogo e devolve a falha")
    func musicSearch() async throws {
        let fake = FakeMusic(arguments: [])
        #expect(try await fake.search(term: "disco").map(\.title) == ["Disco Inventado"])
        #expect(try await fake.search(term: "nada").isEmpty)
        fake.searchError = .failed
        await #expect(throws: MusicPlaybackError.failed) { try await fake.search(term: "disco") }
    }

    @Test("O aviso diz quantos itens ficaram de fora")
    func failureMessage() {
        #expect(TextEditorInsertionPresenter.failureMessage(1) == "1 item não pôde ser lido.")
        #expect(TextEditorInsertionPresenter.failureMessage(3) == "3 itens não puderam ser lidos.")
    }
}
