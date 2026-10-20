import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import MuralKit

@Suite("Importação de conteúdo")
struct ItemImporterTests {
    private func makeImporter() -> ItemImporter {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MuralKitImport-\(UUID().uuidString)/Items")
        return ItemImporter(itemsDirectory: dir)
    }

    /// Gera um PNG 16×16 metade vermelho, metade branco, para testar metadados e paleta.
    private func makeTestPNG(in directory: URL) throws -> URL {
        let width = 16, height = 16
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height where y < height / 2 {
            for x in 0..<width {
                let i = (y * width + x) * 4
                pixels[i + 1] = 0; pixels[i + 2] = 0  // vermelho puro
            }
        }
        let context = try #require(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("teste.png")
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    @Test("Imagem é copiada, ganha metadados e paleta")
    func importsImage() throws {
        let importer = makeImporter()
        let source = try makeTestPNG(in: importer.itemsDirectory.deletingLastPathComponent().appendingPathComponent("src"))
        let item = try importer.importFile(at: source)
        #expect(item.kind == .image)
        #expect(item.title == "teste")
        let copied = try #require(importer.fileURL(for: item))
        #expect(FileManager.default.fileExists(atPath: copied.path))
        let meta = try #require(item.imageMetadata)
        #expect(meta.pixelWidth == 16 && meta.pixelHeight == 16)
        #expect(meta.fileSizeBytes > 0)
        #expect(meta.palette.count == 2)
        #expect(meta.palette[0].red > 0.9 && meta.palette[0].green > 0.9)  // branco primeiro (mais claro)
        #expect(meta.palette[1].red > 0.9 && meta.palette[1].green < 0.1)  // vermelho depois
        importer.removeFile(of: item)
        #expect(!FileManager.default.fileExists(atPath: copied.path))
    }

    @Test("Arquivo inexistente e tipo desconhecido lançam erro")
    func errors() throws {
        let importer = makeImporter()
        #expect(throws: ImportError.fileNotFound(URL(fileURLWithPath: "/nada/aqui.png"))) {
            try importer.importFile(at: URL(fileURLWithPath: "/nada/aqui.png"))
        }
        let dir = importer.itemsDirectory.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let weird = dir.appendingPathComponent("x.zzz")
        try Data().write(to: weird)
        #expect(throws: ImportError.unsupportedType("zzz")) { try importer.importFile(at: weird) }
        #expect(throws: ImportError.emptyText) { try importer.importText("   \n") }
    }

    @Test("Arquivo .txt vira nota com o nome do arquivo como título")
    func importsTextFile() throws {
        let importer = makeImporter()
        let dir = importer.itemsDirectory.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("mooonlight.txt")
        try String(repeating: "Uma ideia por linha. ", count: 20).write(to: url, atomically: true, encoding: .utf8)
        let item = try importer.importFile(at: url)
        #expect(item.kind == .text)
        #expect(item.title == "mooonlight")
        #expect(item.fileName == nil)
    }

    @Test("Texto colado vira post-it ou lista conforme o conteúdo")
    func importsPastedText() throws {
        let importer = makeImporter()
        let sticky = try importer.importText("Comprar tinta")
        #expect(sticky.kind == .sticky && sticky.stickyColor == .yellow)
        let list = try importer.importText("Obra\n- cimento\n- areia")
        #expect(list.kind == .checklist)
        #expect(list.checklist?.sections.first?.entries.count == 2)
    }

    @Test("Dados em memória são gravados como arquivo")
    func importsData() throws {
        let importer = makeImporter()
        let item = try importer.importData(Data([1, 2, 3]), fileExtension: "MOV", kind: .video, title: "Clipe")
        #expect(item.fileName?.hasSuffix(".mov") == true)
        #expect(FileManager.default.fileExists(atPath: importer.fileURL(for: item)!.path))
    }

    /// Lê a pasta de assets real do usuário, se existir; não versiona nada.
    @Test("Todos os arquivos suportados da pasta de assets importam", .enabled(if: FileManager.default.fileExists(atPath: ItemImporterTests.assetsPath)))
    func importsRealAssets() throws {
        let importer = makeImporter()
        let urls = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: Self.assetsPath), includingPropertiesForKeys: nil)
            .filter { ContentClassifier.kind(forFileAt: $0) != nil }
        #expect(!urls.isEmpty)
        for url in urls {
            let item = try importer.importFile(at: url)
            if item.kind == .image { #expect(item.imageMetadata?.pixelWidth ?? 0 > 0, "\(url.lastPathComponent)") }
            if item.kind.storesFile { #expect(FileManager.default.fileExists(atPath: importer.fileURL(for: item)!.path)) }
        }
        try? FileManager.default.removeItem(at: importer.itemsDirectory.deletingLastPathComponent())
    }

    static let assetsPath = NSString(string: "~/Pictures/Assets").expandingTildeInPath
}
