import AppKit
import MuralKit
import UniformTypeIdentifiers

/// Converte o conteúdo da área de transferência (⌘V) em cartões.
enum PasteboardImporter {
    /// Tipos que habilitam o comando Colar no mural.
    static let acceptedTypes: [UTType] = [.fileURL, .image, .pdf, .plainText, .url]

    /// Tipos aceitos por Arquivo › Importar… (os mesmos que viram cartão).
    static let importableTypes: [UTType] = [.image, .movie, .pdf, .plainText]

    /// Lê a área de transferência na ordem: arquivos, imagem PNG, PDF, outra imagem, texto.
    /// Quando nada vira cartão, avisa em `lastError` em vez de ignorar o ⌘V.
    static func paste(from pasteboard: NSPasteboard = .general, into model: BoardModel, parentID: UUID?) {
        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [URL], !urls.isEmpty {
            model.importFiles(urls, into: parentID)
        } else if let png = pasteboard.data(forType: .png) {
            model.importData(png, fileExtension: "png", kind: .image, title: "Imagem colada", into: parentID)
        } else if let pdf = pasteboard.data(forType: .pdf) {
            model.importData(pdf, fileExtension: "pdf", kind: .pdf, title: "PDF colado", into: parentID)
        } else if let png = pngFromAnyImage(on: pasteboard) {
            model.importData(png, fileExtension: "png", kind: .image, title: "Imagem colada", into: parentID)
        } else if let text = pasteboard.string(forType: .string), model.importText(text, into: parentID) != nil {
            return
        } else {
            model.lastError = "O conteúdo copiado não pôde virar um cartão."
        }
    }

    /// Qualquer imagem que o sistema saiba ler (JPEG, TIFF, HEIC…), convertida para PNG.
    private static func pngFromAnyImage(on pasteboard: NSPasteboard) -> Data? {
        guard let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
