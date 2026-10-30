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

    // MARK: Cartões embutidos

    private func cardAttachment(_ card: EmbeddedCard, name: String? = nil, pixels: Int = 0) -> NoteAttachment {
        NoteAttachment(
            fileName: name ?? NoteImageMarkup.cardAttachmentName(for: UUID()), pixelWidth: pixels, pixelHeight: pixels, card: card)
    }

    @Test("Cartão embutido válido não exige arquivo e não conta como mídia; os inválidos têm erro exato")
    func embeddedCardValidation() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let items = try items(root)
        let service = BoardPortablePackageService(availableCapacity: { _ in nil })
        let url = try #require(URL(string: "https://apple.com/mac"))
        let valid = note([
            cardAttachment(.link(LinkInfo(url: url))), cardAttachment(.reminder(ReminderSnapshot(identifier: "", title: "Pão"))),
            cardAttachment(.music(MusicSnapshot(kind: .song, title: "Faixa"))),
        ])
        try await service.validateBoard(Board(items: [valid]), itemsURL: items)

        let badURL = note([cardAttachment(.link(LinkInfo(url: try #require(URL(string: "ftp://exemplo.com/a")))))])
        await assertBoardError(
            Board(items: [badURL]), items,
            .invalidBoard("Cartão embutido de link com endereço inválido: \(badURL.id.uuidString)"))

        let noTitle = note([cardAttachment(.music(MusicSnapshot(kind: .song, title: "  ")))])
        await assertBoardError(Board(items: [noTitle]), items, .invalidMusic(noTitle.id))

        let longReminder = note([cardAttachment(.reminder(ReminderSnapshot(identifier: "", title: String(repeating: "a", count: 1_001))))])
        await assertBoardError(Board(items: [longReminder]), items, .invalidReminder(longReminder.id))

        let badName = note([cardAttachment(.reminder(ReminderSnapshot(identifier: "", title: "x")), name: "\(UUID().uuidString).png")])
        await assertBoardError(Board(items: [badName]), items, .invalidFileName(badName.id))

        let pixels = note([cardAttachment(.reminder(ReminderSnapshot(identifier: "", title: "x")), pixels: 4)])
        await assertBoardError(Board(items: [pixels]), items, .invalidFileName(pixels.id))

        let imageNamedCard = note([NoteAttachment(fileName: NoteImageMarkup.cardAttachmentName(for: UUID()), pixelWidth: 4, pixelHeight: 3)]
        )
        await assertBoardError(Board(items: [imageNamedCard]), items, .invalidFileName(imageNamedCard.id))
    }

    @Test("Arquivo <UUID>.card solto em Items/ é sobra, anexos de mesmo nome na nota são recusados e textos enormes não passam")
    func embeddedCardEdgeCases() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let items = try items(root)
        let reminder = EmbeddedCard.reminder(ReminderSnapshot(identifier: "", title: "Pão"))
        let card = cardAttachment(reminder)
        let stray = items.appendingPathComponent(card.fileName)
        try Data([1]).write(to: stray)
        await assertBoardError(Board(items: [note([card])]), items, .unreferencedAsset(card.fileName))
        try FileManager.default.removeItem(at: stray)

        let twin = note([card, cardAttachment(reminder, name: card.fileName)])
        await assertBoardError(Board(items: [twin]), items, .invalidFileName(twin.id))

        let longList = note([
            cardAttachment(.reminder(ReminderSnapshot(identifier: "", title: "x", listTitle: String(repeating: "a", count: 1_001))))
        ])
        await assertBoardError(Board(items: [longList]), items, .invalidReminder(longList.id))

        let url = try #require(URL(string: "https://apple.com/mac"))
        let huge = note([
            cardAttachment(.link(LinkInfo(url: url, summary: String(repeating: "a", count: BoardImportNormalizer.maximumTextBytes + 1))))
        ])
        #expect(throws: BoardPortablePackageError.textTooLarge(huge.id)) {
            _ = try BoardImportNormalizer.normalize(Board(items: [huge]), itemsURL: items)
        }
    }

    @Test("Exportar e importar levam o cartão embutido, sem arquivo, com o lembrete desligado e as partes locais fora")
    func embeddedCardRoundTrip() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = BoardLibrary(rootDirectory: root)
        let route = try await library.createNamedBoard("Cartões")
        guard case .saved(let id) = route else { throw CocoaError(.fileReadUnknown) }
        let repository = try await library.repository(for: route)
        let url = try #require(URL(string: "https://apple.com/mac"))
        let link = cardAttachment(.link(LinkInfo(url: url, pageTitle: "Mac", previewImageFile: "A1.jpg", preview: .ready(fetchedAt: .now))))
        let reminder = cardAttachment(.reminder(ReminderSnapshot(identifier: "R1", externalIdentifier: "E1", title: "Pão")))
        let text = [link, reminder].compactMap(\.cardID).map { NoteImageMarkup.cardLine(id: $0, title: "Cartão") }.joined(separator: "\n\n")
        let item = note([link, reminder], text: text)
        try await repository.save(
            BoardRepositorySnapshot(
                manifest: BoardManifest(id: id, name: "Cartões", contentRevision: 1), board: Board(items: [item]), workspace: .default))

        let exported = try await library.exportPackage(route)
        #expect(try FileManager.default.contentsOfDirectory(atPath: exported.appendingPathComponent("Items").path).isEmpty)
        let imported = try await library.importPackage(from: exported)
        let snapshot = try #require(await library.open(imported))
        let attachments = try #require(snapshot.board.items.first?.attachments)
        #expect(attachments.map(\.fileName) == [link.fileName, reminder.fileName])
        #expect(attachments.allSatisfy { $0.pixelWidth == 0 && $0.pixelHeight == 0 })
        guard case .link(let importedLink)? = attachments[0].card, case .reminder(let importedReminder)? = attachments[1].card else {
            Issue.record("tipos mudaram")
            return
        }
        #expect(importedLink.previewImageFile == nil && importedLink.preview == .pending && importedLink.pageTitle == "Mac")
        #expect(importedReminder.isDetached && importedReminder.title == "Pão")
        #expect(snapshot.board.formatVersion == 13)
    }
}
