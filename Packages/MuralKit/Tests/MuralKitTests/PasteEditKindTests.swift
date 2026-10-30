import Foundation
import Testing
import UniformTypeIdentifiers

@testable import MuralKit

@Suite("Tipos editáveis antes de colar")
struct PasteEditKindTests {
    @Test("Texto, imagem e PDF têm tipo editável, lido ou não")
    func editableKinds() {
        #expect(PasteEditKind(.text(nil)) == .text)
        #expect(PasteEditKind(.text("Olá")) == .text)
        #expect(PasteEditKind(.image) == .image)
        #expect(PasteEditKind(.pdf) == .pdf)
    }

    @Test("Links, arquivos, música e área vazia não têm tipo editável")
    func nonEditableKinds() {
        let others: [ClipboardKind] = [
            .nothing, .links(count: 0), .links(count: 2), .files(count: 0), .files(count: 3), .music(count: 0), .music(count: 2),
        ]

        for kind in others {
            #expect(PasteEditKind(kind) == nil, "\(kind)")
        }
    }

    @Test("Cada tipo diz o formato, a extensão e o app padrão")
    func properties() {
        #expect(PasteEditKind.text.contentType == .plainText)
        #expect(PasteEditKind.image.contentType == .png)
        #expect(PasteEditKind.pdf.contentType == .pdf)

        #expect(PasteEditKind.text.fileExtension == "txt")
        #expect(PasteEditKind.image.fileExtension == "png")
        #expect(PasteEditKind.pdf.fileExtension == "pdf")

        #expect(PasteEditKind.text.defaultEditorBundleIdentifier == "com.apple.TextEdit")
        #expect(PasteEditKind.image.defaultEditorBundleIdentifier == "com.apple.Preview")
        #expect(PasteEditKind.pdf.defaultEditorBundleIdentifier == "com.apple.Preview")
    }

    @Test("A extensão combina com o formato")
    func extensionMatchesContentType() {
        for kind in PasteEditKind.allCases {
            #expect(kind.contentType.preferredFilenameExtension == kind.fileExtension, "\(kind)")
        }
    }

    @Test("Todos os casos, na ordem")
    func allCasesOrder() {
        #expect(PasteEditKind.allCases == [.text, .image, .pdf])
        #expect(PasteEditKind.allCases.map(\.rawValue) == ["text", "image", "pdf"])
    }
}
