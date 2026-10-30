import AppKit
import MuralKit

/// Lê a área de transferência para o editor de texto, numa ordem só: contatos (vCard), Apple Music, links, imagens e, por
/// último, texto.
///
/// Links só valem quando a área de transferência não tem texto ou o texto é só endereços (`WebLink.urls(inText:)`): um parágrafo
/// copiado que contém um link continua texto. As leituras de cada tipo são as mesmas do ⌘V do mural.
enum TextEditorPasteReader {
    /// Os tipos de dados que o editor aceita colar além dos de texto.
    static let extraTypes: [NSPasteboard.PasteboardType] =
        [ContactVCardReader.vCardType, .URL, .init("WebURLsWithTitlesPboardType"), .init("com.apple.Safari.bookmarkDictionaryList")]
        + [MusicPasteboardReader.genericItemType, MusicPasteboardReader.trackMetadataType, MusicPasteboardReader.playlistNameType]

    static func read(from pasteboard: NSPasteboard) -> TextEditorPaste {
        let contacts = ContactVCardReader.drafts(from: pasteboard)
        if !contacts.isEmpty { return .contacts(contacts) }

        let music = MusicPasteboardReader.drafts(from: pasteboard)
        if !music.isEmpty { return .music(music) }

        // Texto simples que não é só endereços (um parágrafo com um link) continua texto, qualquer que seja o jeito de achar links.
        let text = pasteboard.string(forType: .string)
        let isParagraph = text.map { !$0.isEmpty && WebLink.urls(inText: $0).isEmpty } ?? false
        if !isParagraph {
            let links = LinkPasteboardReader.drafts(from: pasteboard)
            if !links.isEmpty { return .links(links) }
        }

        if let pieces = NoteImagePaste.read(from: pasteboard) { return .images(pieces) }

        if let text, !text.isEmpty { return .text(text) }
        return .nothing
    }
}
