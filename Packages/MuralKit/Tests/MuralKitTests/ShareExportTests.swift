import AVFoundation
import CoreVideo
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import MuralKit

// MARK: Apoio

private let locationKey = "com.apple.metadata:kMDItemWhereFroms"

private func temporaryRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("MuralShare-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Grava uma imagem de verdade com GPS, dono da câmera e números de série.
private func writeImage(_ url: URL, type: UTType = .jpeg, withIdentifyingMetadata: Bool = true) throws {
    let context = try #require(
        CGContext(
            data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
    let image = try #require(context.makeImage())
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
    var properties: [CFString: Any] = [kCGImagePropertyOrientation: 6]
    if withIdentifyingMetadata {
        properties[kCGImagePropertyGPSDictionary] = [
            kCGImagePropertyGPSLatitude: 10.5, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 20.5, kCGImagePropertyGPSLongitudeRef: "E",
        ]
        properties[kCGImagePropertyExifDictionary] = [
            kCGImagePropertyExifCameraOwnerName: "Fulana", kCGImagePropertyExifBodySerialNumber: "CORPO-123",
            kCGImagePropertyExifLensSerialNumber: "LENTE-456", kCGImagePropertyExifUserComment: "ficou",
        ]
    }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
}

private struct ImageTraces {
    var hasGPS: Bool
    var owner: String?
    var bodySerial: String?
    var lensSerial: String?
    var comment: String?
    var orientation: Int?
}

private func traces(of url: URL) throws -> ImageTraces {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
    return ImageTraces(
        hasGPS: properties[kCGImagePropertyGPSDictionary] != nil,
        owner: exif?[kCGImagePropertyExifCameraOwnerName] as? String,
        bodySerial: exif?[kCGImagePropertyExifBodySerialNumber] as? String,
        lensSerial: exif?[kCGImagePropertyExifLensSerialNumber] as? String,
        comment: exif?[kCGImagePropertyExifUserComment] as? String,
        orientation: properties[kCGImagePropertyOrientation] as? Int)
}

private func setAttribute(_ name: String, on url: URL) {
    let value = [UInt8]("https://exemplo.test/arquivo".utf8)
    #expect(setxattr(url.path, name, value, value.count, 0, 0) == 0)
}

private func attributeNames(of url: URL) -> [String] {
    let length = listxattr(url.path, nil, 0, XATTR_NOFOLLOW)
    guard length > 0 else { return [] }
    var buffer = [CChar](repeating: 0, count: length)
    let read = listxattr(url.path, &buffer, length, XATTR_NOFOLLOW)
    return buffer.prefix(max(read, 0)).split(separator: 0).map { String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
}

private func decodeJSON<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        Date(timeIntervalSinceReferenceDate: try decoder.singleValueContainer().decode(Double.self))
    }
    return try decoder.decode(type, from: Data(contentsOf: url))
}

/// Um .mov pequeno com localização nos metadados do contêiner, gravado pelo receptor de pixel buffers do escritor.
private func writeMovie(_ url: URL, location: Bool) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    if location {
        let item = AVMutableMetadataItem()
        item.identifier = .quickTimeMetadataLocationISO6709
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        item.value = "+10.5000+020.5000/" as NSString
        writer.metadata = [item]
    }
    let input = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 48])
    let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: nil)
    try writer.start()
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<6 {
        guard let pixels = solidFrame(shade: Int32(frame * 30)) else { throw CocoaError(.fileWriteUnknown) }
        try await receiver.append(
            CVReadOnlyPixelBuffer(unsafeBuffer: pixels), with: CMTime(value: CMTimeValue(frame), timescale: 10))
    }
    receiver.finish()
    await writer.finishWriting()
    #expect(writer.status == .completed, "\(String(describing: writer.error))")
}

/// Um quadro 64 × 48 de uma cor só. Criado aqui dentro, sai sem outra referência: o receptor exige um buffer só dele.
private func solidFrame(shade: Int32) -> sending CVPixelBuffer? {
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, 64, 48, kCVPixelFormatType_32BGRA, nil, &buffer)
    guard let pixels = buffer else { return nil }
    CVPixelBufferLockBaseAddress(pixels, [])
    if let base = CVPixelBufferGetBaseAddress(pixels) { memset(base, shade, CVPixelBufferGetDataSize(pixels)) }
    CVPixelBufferUnlockBaseAddress(pixels, [])
    return pixels
}

private func hasLocation(_ url: URL) async throws -> Bool {
    let asset = AVURLAsset(url: url)
    var items = try await asset.load(.metadata)
    for format in try await asset.load(.availableMetadataFormats) { items += try await asset.loadMetadata(for: format) }
    return items.contains { item in
        guard let identifier = item.identifier?.rawValue.lowercased() else { return false }
        return identifier.contains("location") || identifier.contains("xyz")
    }
}

/// Um mural salvo com os cartões que a cópia compartilhada precisa tratar.
private struct Fixture {
    var root: URL
    var library: BoardLibrary
    var route: BoardRoute
    var id: BoardID
    var itemsDirectory: URL
    var previews: URL
    var imageItem: UUID
    var linkItem: UUID
    var musicItem: UUID
    var reminderItem: UUID
    var folderItem: UUID
    var noteItem: UUID
}

private func makeFixture(
    image: Bool = true, video: Bool = false, previewFiles: [String] = ["link-image.png", "link-icon.png", "capa.png"]
) async throws -> Fixture {
    let root = try temporaryRoot()
    let library = BoardLibrary(rootDirectory: root, discardPackage: { try FileManager.default.removeItem(at: $0) })
    let route = try await library.createNamedBoard("Original")
    guard case .saved(let id) = route else { throw BoardLibraryError.unavailableRoute(route) }
    let repository = try await library.repository(for: route)
    let previews = root.appendingPathComponent("Previews-\(id.rawValue.uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: previews, withIntermediateDirectories: true)
    for name in previewFiles { try writeImage(previews.appendingPathComponent(name), type: .png, withIdentifyingMetadata: false) }

    let folder = UUID()
    let imageItem = UUID()
    let linkItem = UUID()
    let musicItem = UUID()
    let reminderItem = UUID()
    let noteItem = UUID()
    var items = [
        BoardItem(id: folder, kind: .folder, title: "Pasta", position: BoardPoint(x: 1, y: 2)),
        BoardItem(
            id: linkItem, kind: .link, title: "Site", position: BoardPoint(x: 5, y: 6),
            link: LinkInfo(
                url: URL(string: "https://exemplo.test/pagina?utm_source=news&id=7&fbclid=abc")!, pageTitle: "Página",
                previewImageFile: "link-image.png", iconFile: "link-icon.png", preview: .ready(fetchedAt: Date(timeIntervalSince1970: 5)))),
        BoardItem(
            id: musicItem, kind: .music, title: "Faixa", position: BoardPoint(x: 7, y: 8),
            music: MusicSnapshot(kind: .song, catalogID: "1", libraryID: "LIB-1", title: "Faixa", artworkFile: "capa.png")),
        BoardItem(
            id: reminderItem, kind: .reminder, title: "Lembrar", position: BoardPoint(x: 9, y: 1),
            reminder: ReminderSnapshot(identifier: "ABC-123", externalIdentifier: "EXT-9", title: "Lembrar")),
        BoardItem(
            id: noteItem, kind: .text, title: "Nota", position: BoardPoint(x: 2, y: 2), text: "A visita é na segunda. Medir a parede.",
            keySentences: KeySentenceRecord(source: "A visita é na segunda. Medir a parede.", choices: [:])),
    ]
    if image {
        items.append(
            BoardItem(
                id: imageItem, kind: .image, title: "Foto", position: BoardPoint(x: 3, y: 4), fileName: "foto.jpg",
                imageMetadata: ImageMetadata(pixelWidth: 64, pixelHeight: 48, fileSizeBytes: 1, colorProfile: nil, palette: [])))
    }
    if video {
        items.append(BoardItem(id: UUID(), kind: .video, title: "Filme", position: BoardPoint(x: 4, y: 4), fileName: "filme.mov"))
    }
    let board = Board(items: items)
    let workspace = BoardWorkspaceState(
        contentRevision: 1, canvas: CanvasWorkspaceState(confirmedZoom: 1.5, logicalCenter: BoardPoint(x: 40, y: 50)),
        path: [.collection(folder)], filter: .notes,
        readingPositions: [noteItem: .item(itemID: noteItem, visibleContentY: 12)])
    try await repository.save(
        BoardRepositorySnapshot(manifest: BoardManifest(id: id, name: "Original", contentRevision: 1), board: board, workspace: workspace))
    let itemsDirectory = await repository.packageURL(for: id).appendingPathComponent("Items", isDirectory: true)
    if image { try writeImage(itemsDirectory.appendingPathComponent("foto.jpg")) }
    if video { try await writeMovie(itemsDirectory.appendingPathComponent("filme.mov"), location: true) }
    return Fixture(
        root: root, library: library, route: route, id: id, itemsDirectory: itemsDirectory, previews: previews, imageItem: imageItem,
        linkItem: linkItem, musicItem: musicItem, reminderItem: reminderItem, folderItem: folder, noteItem: noteItem)
}

// MARK: Testes

@Suite("Salvar uma cópia: cópia privada para enviar a outras pessoas")
struct ShareExportTests {
    @Test("Sem a localização: a cópia perde GPS, dono e números de série e mantém o resto; o arquivo interno fica intacto")
    func imageWithoutLocation() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let internalFile = fixture.itemsDirectory.appendingPathComponent("foto.jpg")
        let before = try Data(contentsOf: internalFile)

        let package = try await fixture.library.exportPackage(fixture.route, profile: .share(includeLocation: false))
        let copy = try traces(of: package.appendingPathComponent("Items/foto.jpg"))
        #expect(!copy.hasGPS)
        #expect(copy.owner == nil && copy.bodySerial == nil && copy.lensSerial == nil)
        #expect(copy.comment == "ficou")
        #expect(copy.orientation == 6)

        let original = try traces(of: internalFile)
        #expect(original.hasGPS)
        #expect(original.owner == "Fulana" && original.bodySerial == "CORPO-123" && original.lensSerial == "LENTE-456")
        #expect(try Data(contentsOf: internalFile) == before)

        // O tamanho citado no JSON acompanha o arquivo novo.
        let board = try decodeJSON(Board.self, at: package.appendingPathComponent("board.json"))
        let size = try #require(
            try FileManager.default.attributesOfItem(atPath: package.appendingPathComponent("Items/foto.jpg").path)[.size] as? Int)
        #expect(board.items.first { $0.id == fixture.imageItem }?.imageMetadata?.fileSizeBytes == size)
    }

    @Test("Com a localização: o GPS fica; dono e números de série saem do mesmo jeito")
    func imageWithLocation() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let package = try await fixture.library.exportPackage(fixture.route, profile: .share(includeLocation: true))
        let copy = try traces(of: package.appendingPathComponent("Items/foto.jpg"))
        #expect(copy.hasGPS)
        #expect(copy.owner == nil && copy.bodySerial == nil && copy.lensSerial == nil)
        #expect(try traces(of: fixture.itemsDirectory.appendingPathComponent("foto.jpg")).owner == "Fulana")
    }

    @Test("A regravação quadro a quadro também tira tudo; PNG e GIF, que a cópia sem recompressão não limpa, passam por ela")
    func rewritingRemovesTheData() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        for (type, name) in [(UTType.png, "a.png"), (.gif, "a.gif"), (.tiff, "a.tif"), (.jpeg, "a.jpg")] {
            let url = root.appendingPathComponent(name)
            try writeImage(url, type: type)
            #expect(try ImagePrivacyScrubber.scrub(url, includeLocation: false), "\(name)")
            let result = try traces(of: url)
            #expect(!result.hasGPS && result.owner == nil && result.bodySerial == nil && result.lensSerial == nil, "\(name)")
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            #expect(CGImageSourceGetType(source) as String? == type.identifier, "mesmo tipo em \(name)")
        }
        let forced = root.appendingPathComponent("forcada.jpg")
        try writeImage(forced)
        #expect(try ImagePrivacyScrubber.scrub(forced, includeLocation: true, allowsLosslessCopy: false))
        let result = try traces(of: forced)
        #expect(result.hasGPS && result.owner == nil && result.orientation == 6)
    }

    @Test("Imagem sem nada para tirar não é regravada; arquivo que o ImageIO não lê fica como está")
    func cleanImageIsLeftAlone() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let clean = root.appendingPathComponent("limpa.jpg")
        try writeImage(clean, withIdentifyingMetadata: false)
        let before = try Data(contentsOf: clean)
        #expect(try ImagePrivacyScrubber.scrub(clean, includeLocation: false) == false)
        #expect(try Data(contentsOf: clean) == before)

        let unreadable = root.appendingPathComponent("estranho.png")
        try Data([1, 2, 3]).write(to: unreadable)
        #expect(try ImagePrivacyScrubber.scrub(unreadable, includeLocation: false) == false)
    }

    @Test("Atributos estendidos saem da cópia e continuam no arquivo interno; as datas da cópia são novas")
    func extendedAttributesAndDates() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let internalFile = fixture.itemsDirectory.appendingPathComponent("foto.jpg")
        setAttribute(locationKey, on: internalFile)
        setAttribute("com.apple.metadata:_kMDItemUserTags", on: internalFile)
        let old = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.creationDate: old, .modificationDate: old], ofItemAtPath: internalFile.path)
        let start = Date.now.addingTimeInterval(-2)

        let package = try await fixture.library.exportPackage(fixture.route, profile: .share(includeLocation: false))
        let copy = package.appendingPathComponent("Items/foto.jpg")
        #expect(attributeNames(of: copy).filter { !$0.hasPrefix("com.apple.provenance") }.isEmpty)
        let attributes = try FileManager.default.attributesOfItem(atPath: copy.path)
        #expect(try #require(attributes[.creationDate] as? Date) >= start)
        #expect(try #require(attributes[.modificationDate] as? Date) >= start)

        #expect(attributeNames(of: internalFile).contains(locationKey))
        #expect(attributeNames(of: internalFile).contains("com.apple.metadata:_kMDItemUserTags"))
        let internalAttributes = try FileManager.default.attributesOfItem(atPath: internalFile.path)
        #expect(internalAttributes[.modificationDate] as? Date != nil)
    }

    @Test("Lembrete sem vínculo, música sem id da biblioteca, nota sem frases, link sem rastreamento e estado de tela reduzido")
    func jsonIsReduced() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let package = try await fixture.library.exportPackage(
            fixture.route, profile: .share(includeLocation: false), previewsDirectory: fixture.previews)

        let board = try decodeJSON(Board.self, at: package.appendingPathComponent("board.json"))
        let reminder = try #require(board.items.first { $0.id == fixture.reminderItem }?.reminder)
        #expect(reminder.identifier == "" && reminder.externalIdentifier == nil && reminder.isDetached)
        #expect(reminder.title == "Lembrar")
        #expect(board.items.first { $0.id == fixture.musicItem }?.music?.libraryID == nil)
        #expect(board.items.first { $0.id == fixture.noteItem }?.keySentences == nil)
        let link = try #require(board.items.first { $0.id == fixture.linkItem }?.link)
        #expect(link.url.absoluteString == "https://exemplo.test/pagina?id=7")
        #expect(board.formatVersion == board.requiredFormatVersion)

        let workspace = try decodeJSON(BoardWorkspaceState.self, at: package.appendingPathComponent("view-state.json"))
        #expect(workspace.canvas.confirmedZoom == 1.5)
        #expect(workspace.canvas.logicalCenter == BoardPoint(x: 40, y: 50))
        #expect(workspace.contentRevision == 1)
        #expect(workspace.path.isEmpty && workspace.filter == nil && workspace.readingPositions.isEmpty && workspace.openStretches.isEmpty)
    }

    @Test("As prévias citadas vão em Previews/ sem atributos, o manifesto pede o formato 3 e os cartões voltam a citá-las")
    func previewsAreEmbedded() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        setAttribute(locationKey, on: fixture.previews.appendingPathComponent("capa.png"))
        // Um arquivo que nenhum cartão cita não vai.
        try writeImage(fixture.previews.appendingPathComponent("sobra.png"), type: .png, withIdentifyingMetadata: false)

        let package = try await fixture.library.exportPackage(
            fixture.route, profile: .share(includeLocation: false), previewsDirectory: fixture.previews)
        let embedded = try FileManager.default.contentsOfDirectory(atPath: package.appendingPathComponent("Previews").path).sorted()
        #expect(embedded == ["capa.png", "link-icon.png", "link-image.png"])
        #expect(
            attributeNames(of: package.appendingPathComponent("Previews/capa.png")).filter { !$0.hasPrefix("com.apple.provenance") }.isEmpty
        )
        #expect(attributeNames(of: fixture.previews.appendingPathComponent("capa.png")).contains(locationKey))

        let manifest = try decodeJSON(BoardManifest.self, at: package.appendingPathComponent("manifest.json"))
        #expect(manifest.schemaVersion == 3 && manifest.previewsIncluded == true && manifest.cloud == nil)
        let board = try decodeJSON(Board.self, at: package.appendingPathComponent("board.json"))
        let link = try #require(board.items.first { $0.id == fixture.linkItem }?.link)
        #expect(link.previewImageFile == "link-image.png" && link.iconFile == "link-icon.png")
        #expect(link.preview == .ready(fetchedAt: Date(timeIntervalSince1970: 5)))
        #expect(board.items.first { $0.id == fixture.musicItem }?.music?.artworkFile == "capa.png")
    }

    @Test("Sem pasta de prévias, ou com arquivos ausentes, nada é embutido e o link volta a pendente")
    func noPreviewsMeansPending() async throws {
        let fixture = try await makeFixture(previewFiles: ["link-icon.png"])
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let withoutDirectory = try await fixture.library.exportPackage(fixture.route, profile: .share(includeLocation: false))
        #expect(!FileManager.default.fileExists(atPath: withoutDirectory.appendingPathComponent("Previews").path))
        var manifest = try decodeJSON(BoardManifest.self, at: withoutDirectory.appendingPathComponent("manifest.json"))
        #expect(manifest.schemaVersion == 1 && manifest.previewsIncluded == nil)
        var board = try decodeJSON(Board.self, at: withoutDirectory.appendingPathComponent("board.json"))
        var link = try #require(board.items.first { $0.id == fixture.linkItem }?.link)
        #expect(link.previewImageFile == nil && link.iconFile == nil && link.preview == .pending)

        // Só o ícone existe: vai, e o link passa a contar como buscado.
        let partial = try await fixture.library.exportPackage(
            fixture.route, profile: .share(includeLocation: false), previewsDirectory: fixture.previews)
        manifest = try decodeJSON(BoardManifest.self, at: partial.appendingPathComponent("manifest.json"))
        #expect(manifest.schemaVersion == 3)
        board = try decodeJSON(Board.self, at: partial.appendingPathComponent("board.json"))
        link = try #require(board.items.first { $0.id == fixture.linkItem }?.link)
        #expect(link.previewImageFile == nil && link.iconFile == "link-icon.png")
        #expect(link.preview == .ready(fetchedAt: Date(timeIntervalSince1970: 5)))
        #expect(board.items.first { $0.id == fixture.musicItem }?.music?.artworkFile == nil)
    }

    @Test("Uma prévia grande demais não vai, e a exportação não falha por causa dela")
    func oversizedPreviewIsLeftOut() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try Data(count: LinkPreviewFiles.maximumEmbeddedBytes + 1).write(to: fixture.previews.appendingPathComponent("capa.png"))
        let package = try await fixture.library.exportPackage(
            fixture.route, profile: .share(includeLocation: false), previewsDirectory: fixture.previews)
        let embedded = try FileManager.default.contentsOfDirectory(atPath: package.appendingPathComponent("Previews").path).sorted()
        #expect(embedded == ["link-icon.png", "link-image.png"])
    }

    @Test("O perfil espelho continua igual: GPS e atributos mantidos, sem Previews, formato 1 e estado de tela completo")
    func mirrorIsUnchanged() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let internalFile = fixture.itemsDirectory.appendingPathComponent("foto.jpg")
        setAttribute(locationKey, on: internalFile)

        let package = try await fixture.library.exportPackage(fixture.route)
        let copy = package.appendingPathComponent("Items/foto.jpg")
        #expect(try Data(contentsOf: copy) == Data(contentsOf: internalFile))
        #expect(attributeNames(of: copy).contains(locationKey))
        #expect(!FileManager.default.fileExists(atPath: package.appendingPathComponent("Previews").path))
        let manifest = try decodeJSON(BoardManifest.self, at: package.appendingPathComponent("manifest.json"))
        #expect(manifest.schemaVersion == 1 && manifest.previewsIncluded == nil)
        let manifestText = try String(contentsOf: package.appendingPathComponent("manifest.json"), encoding: .utf8)
        #expect(!manifestText.contains("previewsIncluded"))
        let board = try decodeJSON(Board.self, at: package.appendingPathComponent("board.json"))
        #expect(board.items.first { $0.id == fixture.reminderItem }?.reminder?.identifier == "ABC-123")
        #expect(board.items.first { $0.id == fixture.linkItem }?.link?.previewImageFile == "link-image.png")
        #expect(board.items.first { $0.id == fixture.linkItem }?.link?.url.absoluteString.contains("utm_source") == true)
        let workspace = try decodeJSON(BoardWorkspaceState.self, at: package.appendingPathComponent("view-state.json"))
        #expect(!workspace.path.isEmpty && workspace.filter == .notes && !workspace.readingPositions.isEmpty)
    }

    // MARK: Importação

    @Test("Importar com previewsDirectory copia as prévias para a pasta do id novo e o mural importado volta ao formato 1")
    func importCopiesPreviews() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let package = try await fixture.library.exportPackage(
            fixture.route, profile: .share(includeLocation: false), previewsDirectory: fixture.previews)

        let target = fixture.root.appendingPathComponent("PrevewsImportadas", isDirectory: true)
        let result = try await fixture.library.importPackageWithReport(
            from: package, previewsDirectory: { target.appendingPathComponent($0.rawValue.uuidString, isDirectory: true) })
        let folder = target.appendingPathComponent(result.boardID.rawValue.uuidString, isDirectory: true)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["capa.png", "link-icon.png", "link-image.png"])

        let snapshot = try #require(await fixture.library.open(result.route))
        #expect(snapshot.manifest.schemaVersion == 1 && snapshot.manifest.previewsIncluded == nil)
        let link = try #require(snapshot.board.items.first { $0.link != nil }?.link)
        #expect(link.previewImageFile == "link-image.png" && link.iconFile == "link-icon.png")
        #expect(LinkPreviewFiles(directory: folder).existingURL(for: "link-image.png") != nil)
        let reminder = try #require(snapshot.board.items.first { $0.reminder != nil }?.reminder)
        #expect(reminder.isDetached)
    }

    @Test("Prévia inválida ou não citada é ignorada na importação, sem recusar o pacote; o link volta a pendente")
    func invalidPreviewsAreIgnoredOnImport() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let package = try await fixture.library.exportPackage(
            fixture.route, profile: .share(includeLocation: false), previewsDirectory: fixture.previews)
        let previews = package.appendingPathComponent("Previews")
        // Não é imagem, nome citado por um cartão.
        try Data("não sou imagem".utf8).write(to: previews.appendingPathComponent("link-image.png"))
        // Imagem boa, mas nenhum cartão a cita.
        try writeImage(previews.appendingPathComponent("intrusa.png"), type: .png, withIdentifyingMetadata: false)
        // Grande demais.
        try Data(count: LinkPreviewFiles.maximumEmbeddedBytes + 1).write(to: previews.appendingPathComponent("capa.png"))

        // A conferência estrita da exportação recusa o pacote adulterado...
        let service = BoardPortablePackageService()
        await #expect(throws: BoardPortablePackageError.self) { try await service.validate(package) }

        // ...mas a importação segue, ficando só com o que presta.
        let target = fixture.root.appendingPathComponent("Importadas", isDirectory: true)
        let result = try await fixture.library.importPackageWithReport(
            from: package, previewsDirectory: { target.appendingPathComponent($0.rawValue.uuidString, isDirectory: true) })
        let folder = target.appendingPathComponent(result.boardID.rawValue.uuidString, isDirectory: true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["link-icon.png"])

        let snapshot = try #require(await fixture.library.open(result.route))
        let link = try #require(snapshot.board.items.first { $0.link != nil }?.link)
        #expect(link.previewImageFile == nil && link.iconFile == "link-icon.png")
        #expect(snapshot.board.items.first { $0.music != nil }?.music?.artworkFile == nil)
    }

    @Test("Importar sem previewsDirectory ignora Previews/ e deixa os cartões sem imagem, prontos para buscar de novo")
    func importWithoutDirectory() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let package = try await fixture.library.exportPackage(
            fixture.route, profile: .share(includeLocation: false), previewsDirectory: fixture.previews)
        let route = try await fixture.library.importPackage(from: package)
        let snapshot = try #require(await fixture.library.open(route))
        let link = try #require(snapshot.board.items.first { $0.link != nil }?.link)
        #expect(link.previewImageFile == nil && link.iconFile == nil && link.preview == .pending)
    }

    @Test("Previews/ adulterada com atalho ou subpasta: atalho recusa o pacote, subpasta é ignorada na importação")
    func hostilePreviewEntries() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let package = try await fixture.library.exportPackage(
            fixture.route, profile: .share(includeLocation: false), previewsDirectory: fixture.previews)
        let previews = package.appendingPathComponent("Previews")
        try FileManager.default.createDirectory(at: previews.appendingPathComponent("subpasta"), withIntermediateDirectories: true)
        let service = BoardPortablePackageService()
        await #expect(throws: BoardPortablePackageError.self) { try await service.validate(package) }
        _ = try await fixture.library.importPackage(from: package)

        try FileManager.default.createSymbolicLink(at: previews.appendingPathComponent("atalho.png"), withDestinationURL: fixture.previews)
        await #expect(throws: BoardLibraryError.self) { _ = try await fixture.library.importPackage(from: package) }
    }

    // MARK: Vídeo

    @Test("Vídeo: sem a localização ela sai do contêiner; com a localização o arquivo só perde atributos")
    func videoLocation() async throws {
        let fixture = try await makeFixture(image: false, video: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let internalFile = fixture.itemsDirectory.appendingPathComponent("filme.mov")
        #expect(try await hasLocation(internalFile), "o vídeo de teste precisa nascer com localização")
        setAttribute(locationKey, on: internalFile)

        let without = try await fixture.library.exportPackage(fixture.route, profile: .share(includeLocation: false))
        let cleaned = without.appendingPathComponent("Items/filme.mov")
        #expect(try await hasLocation(cleaned) == false)
        let track = try await AVURLAsset(url: cleaned).loadTracks(withMediaType: .video)
        #expect(track.count == 1)
        #expect(attributeNames(of: cleaned).filter { !$0.hasPrefix("com.apple.provenance") }.isEmpty)

        let with = try await fixture.library.exportPackage(fixture.route, profile: .share(includeLocation: true))
        let kept = with.appendingPathComponent("Items/filme.mov")
        #expect(try await hasLocation(kept))
        #expect(attributeNames(of: kept).filter { !$0.hasPrefix("com.apple.provenance") }.isEmpty)

        // O vídeo interno não mudou.
        #expect(try await hasLocation(internalFile))
        #expect(attributeNames(of: internalFile).contains(locationKey))
    }

    @Test("Vídeo sem localização passa pela exportação sem erro")
    func videoWithoutLocationPasses() async throws {
        let fixture = try await makeFixture(image: false, video: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let internalFile = fixture.itemsDirectory.appendingPathComponent("filme.mov")
        try FileManager.default.removeItem(at: internalFile)
        try await writeMovie(internalFile, location: false)
        let package = try await fixture.library.exportPackage(fixture.route, profile: .share(includeLocation: false))
        #expect(FileManager.default.fileExists(atPath: package.appendingPathComponent("Items/filme.mov").path))
    }

    @Test("Falha ao regravar o vídeo para a exportação inteira com o nome do cartão, sem deixar pacote nem mexer no interno")
    func videoFailureStopsTheExport() async throws {
        let fixture = try await makeFixture(image: false, video: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        await fixture.library.useVideoSanitizer { _, _, _ in throw CocoaError(.fileWriteUnknown) }
        let internalFile = fixture.itemsDirectory.appendingPathComponent("filme.mov")
        let before = try Data(contentsOf: internalFile)

        await #expect(throws: BoardLibraryError.videoLocationNotRemoved("Filme")) {
            _ = try await fixture.library.exportPackage(fixture.route, profile: .share(includeLocation: false))
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: fixture.root.appendingPathComponent("Transfers").path)
        #expect(leftovers.isEmpty)
        #expect(try Data(contentsOf: internalFile) == before)
        #expect(
            BoardLibraryError.videoLocationNotRemoved("Filme").errorDescription
                == "Não foi possível tirar a localização do vídeo “Filme”. Marque “Incluir a localização” para salvar mesmo assim.")

        // Com a localização o vídeo nem passa pela regravação, então a falha não aparece.
        let package = try await fixture.library.exportPackage(fixture.route, profile: .share(includeLocation: true))
        #expect(FileManager.default.fileExists(atPath: package.appendingPathComponent("Items/filme.mov").path))
    }

    @Test("Uma regravação que devolve arquivo vazio também é falha")
    func emptyVideoOutputIsAFailure() async throws {
        let fixture = try await makeFixture(image: false, video: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        await fixture.library.useVideoSanitizer { _, destination, _ in try Data().write(to: destination) }
        await #expect(throws: BoardLibraryError.videoLocationNotRemoved("Filme")) {
            _ = try await fixture.library.exportPackage(fixture.route, profile: .share(includeLocation: false))
        }
    }
}

// MARK: Manifesto e endereços

@Suite("Formato do manifesto com prévias e endereços sem rastreamento")
struct ShareFormatTests {
    @Test("previewsIncluded verdadeiro exige o formato 3 e nil volta ao que o cloud pede")
    func manifestVersions() throws {
        var manifest = BoardManifest(id: BoardID())
        #expect(manifest.schemaVersion == 1 && BoardManifest.currentSchemaVersion == 3)
        manifest.previewsIncluded = true
        #expect(manifest.schemaVersion == 3 && manifest.requiredSchemaVersion == 3)
        manifest.previewsIncluded = nil
        #expect(manifest.schemaVersion == 1)
        manifest.previewsIncluded = false
        #expect(manifest.schemaVersion == 1)
    }

    @Test("O manifesto sem a chave nova codifica como antes e o com a chave faz ida e volta")
    func manifestCoding() throws {
        let plain = BoardManifest(id: BoardID())
        let plainJSON = try String(decoding: JSONEncoder().encode(plain), as: UTF8.self)
        #expect(!plainJSON.contains("previewsIncluded"))
        var withPreviews = plain
        withPreviews.previewsIncluded = true
        let decoded = try JSONDecoder().decode(BoardManifest.self, from: JSONEncoder().encode(withPreviews))
        #expect(decoded == withPreviews && decoded.schemaVersion == 3)
    }

    @Test("Os parâmetros de rastreamento saem; os demais, o fragmento e a ordem ficam")
    func trackingParametersAreRemoved() throws {
        func cleaned(_ text: String) throws -> String {
            WebLink.removingTrackingParameters(from: try #require(URL(string: text))).absoluteString
        }
        #expect(
            try cleaned("https://a.test/p?utm_source=x&id=7&fbclid=1&gclid=2&mc_cid=3&mc_eid=4&q=b%20c#topo")
                == "https://a.test/p?id=7&q=b%20c#topo")
        #expect(try cleaned("https://a.test/p?UTM_Medium=x") == "https://a.test/p")
        #expect(try cleaned("https://a.test/p?id=7") == "https://a.test/p?id=7")
        #expect(try cleaned("mailto:a@b.test?utm_source=x") == "mailto:a@b.test?utm_source=x")
        #expect(try cleaned("https://a.test/p") == "https://a.test/p")
    }
}
