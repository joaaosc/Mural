import AppKit
import ImageIO
import MuralKit
import UniformTypeIdentifiers

/// Converte o conteúdo da área de transferência (⌘V) em cartões.
enum PasteboardImporter {
    /// Tipos que habilitam o comando Colar no mural.
    static let acceptedTypes: [UTType] = [.fileURL, .image, .pdf, .plainText, .url]

    /// Tipos aceitos por Arquivo › Importar… (os mesmos que viram cartão).
    static let importableTypes: [UTType] = [.image, .movie, .pdf, .plainText]

    /// O que foi lido da área de transferência. A leitura é feita na hora, porque o
    /// conteúdo pode mudar; cópia, conversão e gravação acontecem fora do Main Actor.
    enum Content: Sendable {
        case files([URL])
        case data(Data, fileExtension: String, kind: ItemKind, title: String)
        /// Imagem em outro formato (TIFF, JPEG, HEIC, GIF), convertida para PNG ao gravar.
        case imageNeedingConversion(Data)
        case text(String)
        case nothing
    }

    /// Lê na ordem: arquivos, PNG, PDF, outra imagem, texto.
    static func read(from pasteboard: NSPasteboard = .general) -> Content {
        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [URL], !urls.isEmpty {
            return .files(urls)
        }
        if let png = pasteboard.data(forType: .png) {
            return .data(png, fileExtension: "png", kind: .image, title: "Imagem colada")
        }
        if let pdf = pasteboard.data(forType: .pdf) {
            return .data(pdf, fileExtension: "pdf", kind: .pdf, title: "PDF colado")
        }
        if let type = pasteboard.availableType(from: convertibleImageTypes), let data = pasteboard.data(forType: type) {
            return .imageNeedingConversion(data)
        }
        // Representação que só o NSImage sabe ler: converte aqui mesmo (caso raro).
        if let png = pngFromAnyImage(on: pasteboard) {
            return .data(png, fileExtension: "png", kind: .image, title: "Imagem colada")
        }
        if let text = pasteboard.string(forType: .string) {
            return .text(text)
        }
        return .nothing
    }

    private static let convertibleImageTypes: [NSPasteboard.PasteboardType] = [
        .tiff,
        NSPasteboard.PasteboardType(UTType.jpeg.identifier),
        NSPasteboard.PasteboardType(UTType.heic.identifier),
        NSPasteboard.PasteboardType(UTType.gif.identifier),
    ]

    /// Converte uma imagem para PNG fora do Main Actor (ImageIO é seguro entre threads).
    @concurrent
    nonisolated static func pngData(from data: Data) async -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Qualquer imagem que o sistema saiba ler, convertida para PNG.
    private static func pngFromAnyImage(on pasteboard: NSPasteboard) -> Data? {
        guard let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
