import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import MuralKit

@Suite("Importação de pacotes de fora")
struct BoardImportHardeningTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MuralHardening-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func package(at root: URL, board: Board) throws -> URL {
        let package = root.appendingPathComponent("external-\(UUID().uuidString).mural", isDirectory: true)
        try FileManager.default.createDirectory(
            at: package.appendingPathComponent("Items", isDirectory: true), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate)
        }
        try encoder.encode(BoardManifest(id: BoardID(), name: "Fora")).write(to: package.appendingPathComponent("manifest.json"))
        try encoder.encode(board).write(to: package.appendingPathComponent("board.json"))
        return package
    }

    private func pngData(width: Int = 3, height: Int = 2) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func library(_ root: URL) -> BoardLibrary {
        BoardLibrary(rootDirectory: root.appendingPathComponent("Library", isDirectory: true), packageAvailableCapacity: { _ in nil })
    }

    private func imported(_ library: BoardLibrary, from package: URL) async throws -> (board: Board, items: URL) {
        let route = try await library.importPackage(from: package)
        let snapshot = try #require(await library.open(route))
        let id = try savedID(route)
        let repository = try await library.repository(for: route)
        let items = await repository.packageURL(for: id).appendingPathComponent("Items", isDirectory: true)
        return (snapshot.board, items)
    }

    private func savedID(_ route: BoardRoute) throws -> BoardID {
        guard case .saved(let id) = route else { throw BoardPortablePackageError.io("rota inesperada") }
        return id
    }

    private func names(in directory: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
    }

    private func expectRefusal(_ library: BoardLibrary, _ package: URL, _ expected: BoardPortablePackageError) async {
        await #expect(throws: BoardLibraryError.portable(expected)) { _ = try await library.importPackage(from: package) }
    }

    // MARK: Ocultos e entradas reservadas

    @Test("Arquivos ocultos do Finder e de volumes exFAT/SMB são ignorados e não vão para o mural interno")
    func hiddenEntriesAreIgnored() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let item = BoardItem(kind: .image, title: "Foto", fileName: "foto.png")
        let source = try package(at: root, board: Board(items: [item]))
        try pngData().write(to: source.appendingPathComponent("Items/foto.png"))
        for hidden in [".DS_Store", "._manifest.json", "Icon\r", "Items/.DS_Store", "Items/._foto.png", "Items/Icon\r"] {
            try Data([1]).write(to: source.appendingPathComponent(hidden))
        }
        let library = library(root)
        let result = try await imported(library, from: source)
        #expect(try names(in: result.items) == ["foto.png"])

        // Um arquivo comum que ninguém cita continua recusado.
        try Data([1]).write(to: source.appendingPathComponent("Items/sobra.bin"))
        await expectRefusal(library, source, .unreferencedAsset("sobra.bin"))
        try FileManager.default.removeItem(at: source.appendingPathComponent("Items/sobra.bin"))
        try Data([1]).write(to: source.appendingPathComponent("extra.txt"))
        await expectRefusal(library, source, .unexpectedEntry("extra.txt"))
    }

    @Test("QuickLook na raiz é ignorado e não é copiado; dentro de Items continua sendo um arquivo sobrando")
    func quickLookIsReservedAtRoot() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try package(at: root, board: Board(items: [BoardItem(kind: .image, title: "Foto", fileName: "foto.png")]))
        try pngData().write(to: source.appendingPathComponent("Items/foto.png"))
        let quickLook = source.appendingPathComponent("QuickLook", isDirectory: true)
        try FileManager.default.createDirectory(at: quickLook, withIntermediateDirectories: true)
        try Data([1]).write(to: quickLook.appendingPathComponent("Thumbnail.png"))
        let library = library(root)
        let result = try await imported(library, from: source)
        #expect(try names(in: result.items) == ["foto.png"])
        let internalPackage = result.items.deletingLastPathComponent()
        #expect(!FileManager.default.fileExists(atPath: internalPackage.appendingPathComponent("QuickLook").path))

        try Data([1]).write(to: source.appendingPathComponent("Items/QuickLook"))
        await expectRefusal(library, source, .unreferencedAsset("QuickLook"))
    }

    @Test("Nome citado pelo mural que começa com ponto é recusado só na importação")
    func hiddenQuotedNameIsRefusedOnImportOnly() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try package(at: root, board: Board(items: [BoardItem(kind: .image, title: "Foto", fileName: ".x.png")]))
        try pngData().write(to: source.appendingPathComponent("Items/.x.png"))
        let item = try #require(
            try JSONDecoder().decode(Board.self, from: Data(contentsOf: source.appendingPathComponent("board.json"))).items.first)
        await expectRefusal(library(root), source, .invalidFileName(item.id))
        // Exportação e cópias usam o modo normal, que não ganhou essa recusa.
        try await BoardPortablePackageService(availableCapacity: { _ in nil }).validate(source)
    }

    // MARK: Atalhos

    @Test("Atalho quebrado é recusado como atalho")
    func brokenSymlinkIsRefused() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try package(at: root, board: Board())
        let link = source.appendingPathComponent("Items/quebrado")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: root.appendingPathComponent("nao-existe").path)
        // A leitura coordenada devolve o caminho já resolvido (/private/var), então compara-se o nome e não o endereço inteiro.
        do {
            _ = try await library(root).importPackage(from: source)
            Issue.record("a importação deveria recusar o atalho")
        } catch BoardLibraryError.portable(.symlink(let url)) {
            #expect(url.lastPathComponent == "quebrado")
        }
    }

    // MARK: Normalização

    @Test("Posições absurdas são presas a ±1_000_000; as válidas, mesmo negativas ou com fração, ficam como estão")
    func positionsAreClamped() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = BoardItem(kind: .folder, title: "Pasta", position: BoardPoint(x: 1e300, y: -1e300))
        let sticky = BoardItem(
            kind: .sticky, title: "Post-it", parentID: folder.id, position: BoardPoint(x: 5, y: 7.4),
            folderPosition: BoardPoint(x: 1e300, y: 1e300))
        let free = BoardFreeText(text: "oi", position: BoardPoint(x: 1e300, y: -3))
        let source = try package(at: root, board: Board(items: [folder, sticky], freeTexts: [free]))
        let board = try await imported(library(root), from: source).board
        #expect(board.item(id: folder.id)?.position == BoardPoint(x: 1_000_000, y: -1_000_000))
        #expect(board.item(id: sticky.id)?.folderPosition == BoardPoint(x: 1_000_000, y: 1_000_000))
        #expect(board.item(id: sticky.id)?.position == BoardPoint(x: 5, y: 7.4))
        #expect(board.freeTexts.first?.position == BoardPoint(x: 1_000_000, y: -3))
    }

    @Test("Metadados de imagem são relidos do arquivo; sem cabeçalho legível ficam nulos")
    func imageMetadataIsRereadFromFile() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try pngData(width: 3, height: 2)
        let colors = (0..<10).map { PaletteColor(red: Double($0) / 10, green: 0, blue: 0) }
        func metadata(_ width: Int, _ height: Int) -> ImageMetadata {
            ImageMetadata(pixelWidth: width, pixelHeight: height, fileSizeBytes: -5, colorProfile: "sRGB", palette: colors)
        }
        let zero = BoardItem(kind: .image, title: "Zero", fileName: "zero.png", imageMetadata: metadata(0, 0))
        let huge = BoardItem(kind: .image, title: "Enorme", fileName: "enorme.png", imageMetadata: metadata(Int.max, Int.max))
        let broken = BoardItem(kind: .image, title: "Estragada", fileName: "estragada.png", imageMetadata: metadata(10, 10))
        let source = try package(at: root, board: Board(items: [zero, huge, broken]))
        for name in ["zero.png", "enorme.png"] { try data.write(to: source.appendingPathComponent("Items/\(name)")) }
        try Data([1, 2, 3]).write(to: source.appendingPathComponent("Items/estragada.png"))
        let board = try await imported(library(root), from: source).board
        for id in [zero.id, huge.id] {
            let loaded = try #require(board.item(id: id)?.imageMetadata)
            #expect(loaded.pixelWidth == 3)
            #expect(loaded.pixelHeight == 2)
            #expect(loaded.fileSizeBytes == data.count)
            #expect(loaded.palette == Array(colors.prefix(ImageInspector.defaultPaletteSize)))
            #expect(loaded.colorProfile == "sRGB")
        }
        #expect(board.item(id: broken.id)?.imageMetadata == nil)
    }

    @Test("Anexo de nota com dimensões falsas recebe as do arquivo")
    func attachmentDimensionsAreCorrected() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let name = "\(UUID().uuidString).png"
        let note = BoardItem(
            kind: .text, title: "Nota", text: "![x](\(name))",
            attachments: [NoteAttachment(fileName: name, pixelWidth: 0, pixelHeight: Int.max)])
        let source = try package(at: root, board: Board(items: [note]))
        try pngData(width: 4, height: 5).write(to: source.appendingPathComponent("Items/\(name)"))
        let board = try await imported(library(root), from: source).board
        #expect(board.item(id: note.id)?.attachments == [NoteAttachment(fileName: name, pixelWidth: 4, pixelHeight: 5)])
    }

    @Test("Textos livres com id repetido ganham id novo; o primeiro mantém o seu")
    func duplicateFreeTextIDsGetNewIDs() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let texts = (0..<3).map { BoardFreeText(id: id, text: "t\($0)") }
        let source = try package(at: root, board: Board(freeTexts: texts))
        let board = try await imported(library(root), from: source).board
        #expect(board.freeTexts.map(\.text) == ["t0", "t1", "t2"])
        #expect(board.freeTexts.first?.id == id)
        #expect(Set(board.freeTexts.map(\.id)).count == 3)
    }

    @Test("Mais de 10_000 textos livres recusa o pacote antes de copiar")
    func tooManyFreeTextsAreRefused() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let limit = BoardImportNormalizer.maximumFreeTexts
        let accepted = try package(at: root, board: Board(freeTexts: (0..<limit).map { BoardFreeText(text: "\($0)") }))
        let refused = try package(at: root, board: Board(freeTexts: (0...limit).map { BoardFreeText(text: "\($0)") }))
        let library = library(root)
        _ = try await library.importPackage(from: accepted)
        await expectRefusal(library, refused, .tooManyFreeTexts(limit: limit))
        #expect(try FileManager.default.contentsOfDirectory(atPath: await library.importStagingDirectory.path).isEmpty)
    }

    @Test("Texto acima de 4 MB recusa o pacote; título e etiqueta longos são cortados")
    func textLimits() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let limit = BoardImportNormalizer.maximumTextBytes
        let library = library(root)

        let atLimit = BoardItem(kind: .text, title: "Limite", text: String(repeating: "a", count: limit))
        _ = try await library.importPackage(from: try package(at: root, board: Board(items: [atLimit])))

        let note = BoardItem(kind: .text, title: "Nota", text: String(repeating: "a", count: limit + 1))
        await expectRefusal(library, try package(at: root, board: Board(items: [note])), .textTooLarge(note.id))
        let entry = ChecklistEntry(text: String(repeating: "b", count: limit + 1))
        let list = BoardItem(
            kind: .checklist, title: "Lista",
            checklist: ChecklistDocument(title: "Lista", sections: [ChecklistSection(title: "S", entries: [entry])]))
        await expectRefusal(library, try package(at: root, board: Board(items: [list])), .textTooLarge(list.id))

        let long = BoardItem(kind: .text, title: String(repeating: "t", count: 5_000), tag: String(repeating: "g", count: 500))
        let board = try await imported(library, from: try package(at: root, board: Board(items: [long]))).board
        #expect(board.item(id: long.id)?.title.count == 1_000)
        #expect(board.item(id: long.id)?.tag?.count == 100)
    }

    @Test("Lembrete chega desligado do app Lembretes, com o resto do estado")
    func reminderArrivesDetached() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = ReminderSnapshot(
            identifier: "ABC-123", externalIdentifier: "ext", title: "Comprar pão", isCompleted: true, listTitle: "Casa")
        let card = BoardItem(kind: .reminder, title: "Comprar pão", reminder: snapshot)
        let board = try await imported(library(root), from: try package(at: root, board: Board(items: [card]))).board
        var expected = snapshot
        expected.identifier = ""
        expected.externalIdentifier = nil
        #expect(board.item(id: card.id)?.reminder == expected)
    }

    @Test("Tentativas de prévia de link ficam entre 0 e 64")
    func linkAttemptsAreClamped() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Date(timeIntervalSinceReferenceDate: 1000)
        func card(_ attempts: Int) throws -> BoardItem {
            BoardItem(
                kind: .link, title: "Link",
                link: LinkInfo(url: try #require(URL(string: "https://example.com")), preview: .failed(at: date, attempts: attempts)))
        }
        let huge = try card(Int.max)
        let negative = try card(Int.min)
        let board = try await imported(library(root), from: try package(at: root, board: Board(items: [huge, negative]))).board
        #expect(board.item(id: huge.id)?.link?.preview == .failed(at: date, attempts: 64))
        #expect(board.item(id: negative.id)?.link?.preview == .failed(at: date, attempts: 0))
    }

    // MARK: Mural interno (R1/R2)

    @Test("Exportar um mural interno com valores fora dos limites da importação continua funcionando")
    func exportKeepsWorkingWithOutOfRangeValues() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = library(root)
        let route = try await library.createNamedBoard("Interno")
        let id = try savedID(route)
        let repository = try await library.repository(for: route)
        let duplicate = UUID()
        let note = BoardItem(
            kind: .text, title: String(repeating: "t", count: 2_000), position: BoardPoint(x: 1e300, y: 1e300),
            tag: String(repeating: "g", count: 300))
        let board = Board(items: [note], freeTexts: [BoardFreeText(id: duplicate, text: "a"), BoardFreeText(id: duplicate, text: "b")])
        try await repository.save(
            BoardRepositorySnapshot(manifest: BoardManifest(id: id, name: "Interno", contentRevision: 1), board: board, workspace: .default)
        )
        let exported = try await library.exportPackage(route)
        let data = try Data(contentsOf: exported.appendingPathComponent("board.json"))
        let exportedBoard = try JSONDecoder().decode(Board.self, from: data)
        #expect(exportedBoard.items.first?.position == BoardPoint(x: 1e300, y: 1e300))
        #expect(exportedBoard.items.first?.title.count == 2_000)
        #expect(exportedBoard.freeTexts.count == 2)
    }
}
