import AppKit
import MuralKit
import UniformTypeIdentifiers

/// Lê da área de transferência as imagens que podem entrar numa nota (⌘V) e as grava como anexos.
enum NoteImagePaste {
    /// De onde vem os bytes de uma imagem a anexar.
    enum Source: Sendable {
        case file(URL)
        case data(Data, fileExtension: String)
        /// Imagem em outro formato (TIFF etc.), convertida para PNG ao gravar.
        case needsPNGConversion(Data)
    }

    /// Um pedaço do que foi colado, na ordem original.
    enum Piece: Sendable {
        case text(String)
        case image(Source)
    }

    private static let objectReplacement: Character = "\u{FFFC}"
    private static let attachmentExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif"]
    private static let webArchiveType = NSPasteboard.PasteboardType("com.apple.webarchive")

    /// Lê as peças a colar; `nil` quando não há imagem e o colar segue como texto.
    ///
    /// Ordem: arquivos, texto formatado com imagens dentro, dados de imagem.
    static func read(from pasteboard: NSPasteboard) -> [Piece]? {
        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [URL], !urls.isEmpty {
            let images = urls.filter { ContentClassifier.kind(forFileAt: $0) == .image }
            return images.isEmpty ? nil : images.map { .image(.file($0)) }
        }
        if let attributed = richText(from: pasteboard) {
            let pieces = pieces(from: attributed)
            return pieces.contains { if case .image = $0 { true } else { false } } ? pieces : nil
        }
        if let source = imageSource(from: pasteboard) {
            return [.image(source)]
        }
        return nil
    }

    /// A fonte de uma imagem que chegou como dados: nos formatos que o anexo guarda, como veio; nos outros, convertida para PNG ao
    /// gravar.
    static func source(data: Data, fileExtension: String) -> Source {
        let name = fileExtension.lowercased()
        guard attachmentExtensions.contains(name) else { return .needsPNGConversion(data) }
        return .data(data, fileExtension: name == "jpeg" ? "jpg" : name)
    }

    /// Grava a imagem em `Items/` (ainda sem citar) fora do Main Actor.
    static func store(_ source: Source, with model: BoardModel) async -> NoteAttachment? {
        switch source {
        case .file(let url):
            return await model.prepareNoteImage(fileAt: url)
        case .data(let data, let fileExtension):
            return await model.prepareNoteImage(data: data, fileExtension: fileExtension)
        case .needsPNGConversion(let data):
            guard let png = await PasteboardImporter.pngData(from: data) else { return nil }
            return await model.prepareNoteImage(data: png, fileExtension: "png")
        }
    }

    // MARK: Leitura

    private static func richText(from pasteboard: NSPasteboard) -> NSAttributedString? {
        for type in [NSPasteboard.PasteboardType.rtfd, .init("NeXT RTFD pasteboard type")] {
            if let data = pasteboard.data(forType: type),
                let text = NSAttributedString(rtfd: data, documentAttributes: nil)
            {
                return text
            }
        }
        if let data = pasteboard.data(forType: webArchiveType),
            let text = try? NSAttributedString(
                data: data, options: [.documentType: NSAttributedString.DocumentType.webArchive],
                documentAttributes: nil)
        {
            return text
        }
        return nil
    }

    private static func pieces(from text: NSAttributedString) -> [Piece] {
        var result: [Piece] = []
        var buffer = ""
        func flush() {
            if !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(.text(buffer)) }
            buffer = ""
        }
        let string = text.string as NSString
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            let chunk = string.substring(with: range)
            guard let attachment = value as? NSTextAttachment else {
                buffer += chunk.filter { $0 != objectReplacement }
                return
            }
            buffer += chunk.filter { $0 != objectReplacement }
            if let source = source(of: attachment) {
                flush()
                result.append(.image(source))
            }
        }
        flush()
        return result
    }

    private static func source(of attachment: NSTextAttachment) -> Source? {
        if let wrapper = attachment.fileWrapper, let data = wrapper.regularFileContents {
            let name = wrapper.preferredFilename ?? wrapper.filename ?? ""
            let ext = (name as NSString).pathExtension.lowercased()
            if attachmentExtensions.contains(ext) {
                return .data(data, fileExtension: ext == "jpeg" ? "jpg" : ext)
            }
            if NSImage(data: data) != nil { return .needsPNGConversion(data) }
        }
        if let tiff = attachment.image?.tiffRepresentation { return .needsPNGConversion(tiff) }
        return nil
    }

    private static func imageSource(from pasteboard: NSPasteboard) -> Source? {
        let jpeg = NSPasteboard.PasteboardType(UTType.jpeg.identifier)
        let heic = NSPasteboard.PasteboardType(UTType.heic.identifier)
        let gif = NSPasteboard.PasteboardType(UTType.gif.identifier)
        if let data = pasteboard.data(forType: .png) { return .data(data, fileExtension: "png") }
        if let data = pasteboard.data(forType: jpeg) { return .data(data, fileExtension: "jpg") }
        if let data = pasteboard.data(forType: heic) { return .data(data, fileExtension: "heic") }
        if let data = pasteboard.data(forType: gif) { return .data(data, fileExtension: "gif") }
        if let data = pasteboard.data(forType: .tiff) { return .needsPNGConversion(data) }
        if let tiff = NSImage(pasteboard: pasteboard)?.tiffRepresentation { return .needsPNGConversion(tiff) }
        return nil
    }
}
