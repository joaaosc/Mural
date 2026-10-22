import AppKit
import Foundation
import MuralKit
import Testing

@testable import Mural

/// Mural numa pasta temporária e área de transferência privada (nunca a geral), tudo apagado em `tearDown()`.
@MainActor
final class LinkImportFixture {
    let directory: URL
    let model: BoardModel
    let pasteboard: NSPasteboard

    init(items: [BoardItem] = []) {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MuralTests-Links-\(UUID().uuidString)", isDirectory: true)
        model = BoardModel(
            board: Board(items: items), store: BoardStore(directory: directory.appendingPathComponent("Mural", isDirectory: true)),
            persistence: .deferred)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("MuralTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
    }

    func tearDown() {
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: directory)
    }

    /// Substitui o conteúdo da área de transferência privada.
    func write(_ items: NSPasteboardItem...) {
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
    }

    /// Acrescenta um tipo antigo (sem identificador UTI, como `WebURLsWithTitlesPboardType`) à área inteira.
    func addLegacy(_ plist: Any, forType type: NSPasteboard.PasteboardType) {
        pasteboard.addTypes([type], owner: nil)
        pasteboard.setPropertyList(plist, forType: type)
    }

    /// ⌘V na área privada: lê como o mural lê e cria o cartão como `BoardWindowSession.importPasted` cria,
    /// mas direto no modelo. Texto solto vira o tipo sugerido, sem o popup.
    func paste(into parentID: UUID? = nil) async {
        switch PasteboardImporter.read(from: pasteboard) {
        case .files(let urls):
            _ = model.importFiles(urls, into: parentID)
        case .data(let data, let fileExtension, let kind, let title):
            _ = model.importData(data, fileExtension: fileExtension, kind: kind, title: title, into: parentID)
        case .imageNeedingConversion(let data):
            guard let png = await PasteboardImporter.pngData(from: data) else {
                model.lastError = "A imagem copiada não pôde ser lida."
                return
            }
            _ = model.importData(png, fileExtension: "png", kind: .image, title: "Imagem colada", into: parentID)
        case .links(let drafts):
            if model.importLinks(drafts, into: parentID).isEmpty {
                model.lastError = "O conteúdo copiado não pôde virar um cartão."
            }
        case .text(let text):
            if model.importText(text, into: parentID) == nil {
                model.lastError = "O conteúdo copiado não pôde virar um cartão."
            }
        case .nothing:
            model.lastError = "O conteúdo copiado não pôde virar um cartão."
        }
    }

    var links: [BoardItem] { model.board.items.filter { $0.kind == .link } }

    // MARK: Arquivos de apoio

    /// Imagem 40×30 gerada no teste: nenhum arquivo de imagem é versionado.
    static func imageData(_ type: NSBitmapImageRep.FileType) throws -> Data {
        let rep = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 30, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for x in 0..<40 {
            for y in 0..<30 {
                rep.setColor(x < 20 ? .systemOrange : .systemIndigo, atX: x, y: y)
            }
        }
        if type == .tiff { return try #require(rep.tiffRepresentation) }
        return try #require(rep.representation(using: type, properties: [:]))
    }

    /// O arquivo guardado de um cartão começa com a assinatura de um PNG.
    func storedFileIsPNG(_ item: BoardItem) -> Bool {
        guard let url = model.fileURL(for: item), let data = try? Data(contentsOf: url) else { return false }
        return data.starts(with: [0x89, 0x50, 0x4E, 0x47])
    }
}
