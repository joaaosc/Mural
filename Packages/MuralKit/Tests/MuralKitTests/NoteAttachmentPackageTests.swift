import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import MuralKit

@Suite("Pacotes .mural com anexos de notas")
struct NoteAttachmentPackageTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MuralAttach-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func pngData(width: Int = 4, height: Int = 3) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func attachment(_ name: String = "\(UUID().uuidString).png") -> NoteAttachment {
        NoteAttachment(fileName: name, pixelWidth: 4, pixelHeight: 3)
    }

    private func note(_ attachments: [NoteAttachment]?, text: String? = nil) -> BoardItem {
        BoardItem(kind: .text, title: "Nota", text: text, attachments: attachments)
    }

    private func items(_ root: URL) throws -> URL {
        let url = root.appendingPathComponent("Items", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func assertBoardError(_ board: Board, _ items: URL, _ expected: BoardPortablePackageError) async {
        let service = BoardPortablePackageService(availableCapacity: { _ in nil })
        do {
            try await service.validateBoard(board, itemsURL: items)
            Issue.record("esperado \(expected), a validação passou")
        } catch {
            #expect((error as? BoardPortablePackageError) == expected)
        }
    }

    @Test("Exportar leva o anexo para Items/ e importar mantém nota e arquivo")
    func roundTripKeepsAttachment() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = BoardLibrary(rootDirectory: root)
        let route = try await library.createNamedBoard("Anexos")
        guard case .saved(let id) = route else { throw CocoaError(.fileReadUnknown) }
        let repository = try await library.repository(for: route)
        let name = "\(UUID().uuidString).png"
        let cited = "\(UUID().uuidString).png"
        let item = note([attachment(name)], text: "![Imagem](\(name))\n\n![Ausente](\(cited))")
        let board = Board(items: [item])
        try await repository.save(
            BoardRepositorySnapshot(
                manifest: BoardManifest(id: id, name: "Anexos", contentRevision: 1), board: board, workspace: .default))
        let data = try pngData()
        let source = await repository.packageURL(for: id).appendingPathComponent("Items", isDirectory: true)
        try data.write(to: source.appendingPathComponent(name))

        let exported = try await library.exportPackage(route)
        #expect(try Data(contentsOf: exported.appendingPathComponent("Items/\(name)")) == data)
        #expect(!FileManager.default.fileExists(atPath: exported.appendingPathComponent("Items/\(cited)").path))

        let imported = try await library.importPackage(from: exported)
        let snapshot = try #require(await library.open(imported))
        #expect(snapshot.board == board)
        let importedRepository = try await library.repository(for: imported)
        guard case .saved(let importedID) = imported else { throw CocoaError(.fileReadUnknown) }
        let copy = await importedRepository.packageURL(for: importedID).appendingPathComponent("Items/\(name)")
        #expect(try Data(contentsOf: copy) == data)
    }

    @Test("Anexo ausente, nome inseguro, tipo errado, colisão, não imagem e tamanho zero têm erro exato")
    func attachmentErrorsAreExact() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let items = try items(root)

        let missing = attachment()
        await assertBoardError(Board(items: [note([missing])]), items, .missingAsset(missing.fileName))

        let unsafe = note([attachment("../escape.png")])
        await assertBoardError(Board(items: [unsafe]), items, .invalidFileName(unsafe.id))

        let notNote = BoardItem(kind: .folder, title: "Pasta", attachments: [attachment()])
        await assertBoardError(Board(items: [notNote]), items, .invalidFileName(notNote.id))

        let shared = "\(UUID().uuidString).png"
        try pngData().write(to: items.appendingPathComponent(shared))
        let media = BoardItem(kind: .image, title: "Imagem", fileName: shared)
        await assertBoardError(Board(items: [media, note([attachment(shared)])]), items, .duplicateAsset(shared))

        let fake = attachment()
        try Data([1, 2, 3]).write(to: items.appendingPathComponent(fake.fileName))
        let fakeNote = note([fake])
        await assertBoardError(
            Board(items: [fakeNote]), items, .assetKindMismatch(fakeNote.id, expected: .image, actual: nil))

        let empty = note([NoteAttachment(fileName: "\(UUID().uuidString).png", pixelWidth: 0, pixelHeight: 3)])
        await assertBoardError(Board(items: [empty]), items, .invalidFileName(empty.id))
    }

    @Test("Duas notas citando o mesmo anexo passam")
    func sharedAttachmentIsAllowed() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let items = try items(root)
        let shared = attachment()
        try pngData().write(to: items.appendingPathComponent(shared.fileName))
        let service = BoardPortablePackageService(availableCapacity: { _ in nil })
        try await service.validateBoard(Board(items: [note([shared]), note([shared])]), itemsURL: items)
    }
}
