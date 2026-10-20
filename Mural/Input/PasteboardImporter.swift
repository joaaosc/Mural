import AppKit
import MuralKit
import UniformTypeIdentifiers

/// Converte o conteúdo da área de transferência (⌘V) em cartões.
enum PasteboardImporter {
    /// Tipos que habilitam o comando Colar no mural.
    static let acceptedTypes: [UTType] = [.fileURL, .png, .tiff, .jpeg, .image, .pdf, .movie, .rtf, .utf8PlainText, .plainText, .url]

    /// Lê a área de transferência na ordem: arquivos, imagem, texto.
    /// - Returns: quantos cartões foram criados.
    @discardableResult
    static func paste(from pasteboard: NSPasteboard = .general, into model: BoardModel, parentID: UUID?) -> Int {
        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [URL], !urls.isEmpty {
            return model.importFiles(urls, into: parentID).count
        }
        if let png = pasteboard.data(forType: .png) ?? pngFromTIFF(pasteboard.data(forType: .tiff)) {
            return model.importData(png, fileExtension: "png", kind: .image, title: "Imagem colada", into: parentID) == nil ? 0 : 1
        }
        if let text = pasteboard.string(forType: .string) {
            return model.importText(text, into: parentID) == nil ? 0 : 1
        }
        return 0
    }

    private static func pngFromTIFF(_ data: Data?) -> Data? {
        guard let data, let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// Abre o acesso de sandbox de URLs vindas do seletor de arquivos durante a importação.
enum SecurityScopedAccess {
    static func withAccess<T>(to urls: [URL], _ body: () -> T) -> T {
        let opened = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { opened.forEach { $0.stopAccessingSecurityScopedResource() } }
        return body()
    }
}
