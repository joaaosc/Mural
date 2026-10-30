import CoreGraphics
import Foundation
import ImageIO
import MuralKit
import Testing
import UniformTypeIdentifiers

@testable import Mural

@MainActor
@Suite("Fotos dos contatos")
struct ContactThumbnailStoreTests {
    private func pngData() throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func makeSetup() throws -> (root: URL, files: LinkPreviewFiles, model: BoardModel) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MuralThumb-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let files = LinkPreviewFiles(directory: root.appendingPathComponent("Previews", isDirectory: true))
        let model = BoardModel(
            board: Board(), store: BoardStore(directory: root.appendingPathComponent("Board")), persistence: .immediate)
        return (root, files, model)
    }

    private func leftovers(_ files: LinkPreviewFiles) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: files.directory.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }
    }

    @Test("A foto é gravada e ligada ao cartão")
    func storesAndLinks() async throws {
        let (root, files, model) = try makeSetup()
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = ContactSnapshot(givenName: "Ana", familyName: "Foto")
        let created = model.importContacts([snapshot])
        let store = ContactThumbnailStore(model: model, files: files)
        store.store([ContactDraft(snapshot: snapshot, thumbnailData: try pngData())], for: created)
        await store.waitUntilIdle()

        let name = try #require(model.item(id: created[0].id)?.contact?.thumbnailFile)
        #expect(files.existingURL(for: name) != nil)
    }

    @Test("Com o cartão apagado antes do fim, nada é ligado e nenhum arquivo sobra")
    func removedItemLeavesNothing() async throws {
        let (root, files, model) = try makeSetup()
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = ContactSnapshot(givenName: "Ana", familyName: "Foto")
        let created = model.importContacts([snapshot])
        let store = ContactThumbnailStore(model: model, files: files)
        store.store([ContactDraft(snapshot: snapshot, thumbnailData: try pngData())], for: created)
        model.delete(created[0].id)
        await store.waitUntilIdle()

        #expect(model.item(id: created[0].id) == nil)
        #expect(leftovers(files).isEmpty)
    }

    @Test("Com a sessão fechada, o arquivo é descartado")
    func inactiveStoreDiscards() async throws {
        let (root, files, model) = try makeSetup()
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = ContactSnapshot(givenName: "Ana", familyName: "Foto")
        let created = model.importContacts([snapshot])
        let store = ContactThumbnailStore(model: model, files: files, isActive: { false })
        store.store([ContactDraft(snapshot: snapshot, thumbnailData: try pngData())], for: created)
        await store.waitUntilIdle()

        #expect(model.item(id: created[0].id)?.contact?.thumbnailFile == nil)
        #expect(leftovers(files).isEmpty)
    }
}
