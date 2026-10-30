import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Para quem e para que o pacote de um mural é montado.
public enum BoardExportProfile: Sendable, Equatable {
    /// O pacote completo de sempre: é o que a cópia do iCloud Drive e o backup usam, sem nenhuma limpeza.
    case mirror
    /// Cópia privada para enviar a outras pessoas: sem dados do Mac de origem (vínculos, origem dos downloads, números de série,
    /// posição de leitura) e com as imagens das prévias. `includeLocation` mantém a localização de fotos e vídeos.
    case share(includeLocation: Bool)
}

/// Deixa a pasta de passagem de um pacote pronta para ser enviada a outras pessoas.
///
/// Só mexe na pasta de passagem montada em `Transfers/`: os arquivos dali são clones do mural interno, e trocar o clone por um
/// arquivo novo (ou tirar os atributos dele) não altera o original. Nada aqui lê ou grava no mural interno além de copiar as
/// imagens das prévias.
struct BoardShareExporter {
    /// Grava em `destination` uma cópia de `source` sem os metadados de localização, no mesmo contêiner.
    typealias VideoSanitizer = @Sendable (_ source: URL, _ destination: URL, _ fileType: AVFileType) async throws -> Void

    let includeLocation: Bool
    let previewsDirectory: URL?
    let sanitizeVideo: VideoSanitizer
    let now: Date

    func apply(to staging: URL) async throws {
        let manifestURL = staging.appendingPathComponent("manifest.json")
        let boardURL = staging.appendingPathComponent("board.json")
        let workspaceURL = staging.appendingPathComponent("view-state.json")
        var manifest = try Self.decode(BoardManifest.self, at: manifestURL)
        var board = try Self.decode(Board.self, at: boardURL)
        let workspace = try Self.decode(BoardWorkspaceState.self, at: workspaceURL)

        let sizes = try await cleanMedia(in: staging.appendingPathComponent("Items", isDirectory: true), board: board)
        let embedded = try embedPreviews(of: board, into: staging.appendingPathComponent("Previews", isDirectory: true))

        board.items = board.items.map { Self.sharedItem($0, embedded: embedded, sizes: sizes, now: now) }
        board.formatVersion = board.requiredFormatVersion
        manifest.previewsIncluded = embedded.isEmpty ? nil : true
        // Só o enquadramento e a revisão: caminho aberto, filtro, posição de leitura e trechos abertos são de quem usava o mural.
        let reducedWorkspace = BoardWorkspaceState(
            schemaVersion: workspace.schemaVersion, contentRevision: workspace.contentRevision, canvas: workspace.canvas)

        try Self.encode(manifest).write(to: manifestURL, options: .atomic)
        try Self.encode(board).write(to: boardURL, options: .atomic)
        try Self.encode(reducedWorkspace).write(to: workspaceURL, options: .atomic)
    }

    // MARK: Cartões

    /// O cartão como vai na cópia: sem as partes locais, sem vínculo com o Lembretes, sem rastreamento no endereço, e com as
    /// prévias que foram embutidas de volta.
    static func sharedItem(_ item: BoardItem, embedded: Set<String>, sizes: [String: Int], now: Date) -> BoardItem {
        var copy = SharedFieldPolicy.shared(item)
        if var reminder = copy.reminder {
            reminder.identifier = ""
            reminder.externalIdentifier = nil
            copy.reminder = reminder
        }
        if var link = copy.link, let original = item.link {
            link.url = WebLink.removingTrackingParameters(from: link.url)
            link.previewImageFile = original.previewImageFile.flatMap { embedded.contains($0) ? $0 : nil }
            link.iconFile = original.iconFile.flatMap { embedded.contains($0) ? $0 : nil }
            if link.previewImageFile != nil || link.iconFile != nil {
                if case .ready = original.preview { link.preview = original.preview } else { link.preview = .ready(fetchedAt: now) }
            }
            copy.link = link
        }
        if var music = copy.music, let name = item.music?.artworkFile, embedded.contains(name) {
            music.artworkFile = name
            copy.music = music
        }
        if let name = copy.fileName, let size = sizes[name], var metadata = copy.imageMetadata, metadata.fileSizeBytes != size {
            metadata.fileSizeBytes = size
            copy.imageMetadata = metadata
        }
        return copy
    }

    // MARK: Mídia

    /// Limpa cada arquivo de `Items/` e devolve o tamanho final de cada um. Imagens perdem o dono da câmera e os números de série
    /// (e o GPS, sem `includeLocation`); vídeos perdem a localização, sem `includeLocation`; todos perdem os atributos estendidos
    /// (origem do download, etiquetas do Finder) e ganham datas novas.
    private func cleanMedia(in items: URL, board: Board) async throws -> [String: Int] {
        let titles = Self.titlesByFile(board)
        var sizes: [String: Int] = [:]
        let names = try FileManager.default.contentsOfDirectory(atPath: items.path).filter { !$0.hasPrefix(".") }.sorted()
        for name in names {
            let url = items.appendingPathComponent(name)
            let title = titles[name] ?? name
            switch ContentClassifier.kind(forFileAt: url) {
            case .image:
                do {
                    _ = try ImagePrivacyScrubber.scrub(url, includeLocation: includeLocation)
                } catch {
                    throw BoardLibraryError.imageMetadataNotRemoved(title)
                }
            case .video where !includeLocation:
                try await scrubVideo(at: url, title: title)
            default:
                break
            }
            try Self.stripFileTraces(at: url, now: now)
            sizes[name] = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        }
        return sizes
    }

    /// Regrava o vídeo sem a localização, sem recomprimir. Se não der, a exportação inteira para: a cópia não sai com a localização
    /// que a pessoa não quis mandar.
    private func scrubVideo(at url: URL, title: String) async throws {
        guard let type = UTType(filenameExtension: url.pathExtension) else { throw BoardLibraryError.videoLocationNotRemoved(title) }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".share-\(UUID().uuidString).\(url.pathExtension)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try await sanitizeVideo(url, temporary, AVFileType(rawValue: type.identifier))
            guard Self.hasContent(temporary) else { throw BoardLibraryError.videoLocationNotRemoved(title) }
            try FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: temporary, to: url)
        } catch {
            throw BoardLibraryError.videoLocationNotRemoved(title)
        }
    }

    /// A implementação de verdade: exportação sem recompressão e sem os metadados que não devem ser compartilhados.
    static func sanitizeVideoForSharing(source: URL, destination: URL, fileType: AVFileType) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough),
            session.supportedFileTypes.contains(fileType)
        else { throw CocoaError(.fileWriteUnsupportedScheme) }
        session.metadataItemFilter = .forSharing()
        try await session.export(to: destination, as: fileType)
    }

    private static func hasContent(_ url: URL) -> Bool {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0) > 0
    }

    /// Nome do arquivo em `Items/` → título do cartão a que ele pertence (o do anexo é o da nota).
    private static func titlesByFile(_ board: Board) -> [String: String] {
        var titles: [String: String] = [:]
        for item in board.items {
            for name in item.assetFileNames where titles[name] == nil { titles[name] = item.title }
        }
        return titles
    }

    // MARK: Prévias

    /// Copia para `directory` os arquivos de prévia e de capa que os cartões citam e que existem na pasta de prévias e cabem numa
    /// cópia. Devolve os nomes copiados; sem nenhum, a pasta nem é criada.
    private func embedPreviews(of board: Board, into directory: URL) throws -> Set<String> {
        guard let previewsDirectory else { return [] }
        let files = LinkPreviewFiles(directory: previewsDirectory)
        var embedded = Set<String>()
        for item in board.items {
            for name in [item.link?.previewImageFile, item.link?.iconFile, item.music?.artworkFile].compactMap({ $0 }) {
                guard !embedded.contains(name), let source = files.existingURL(for: name), LinkPreviewFiles.isEmbeddable(at: source)
                else { continue }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let target = directory.appendingPathComponent(name)
                try FileManager.default.copyItem(at: source, to: target)
                try Self.stripFileTraces(at: target, now: now)
                embedded.insert(name)
            }
        }
        return embedded
    }

    // MARK: Rastros do arquivo

    /// Tira todos os atributos estendidos do arquivo (origem do download, etiquetas, quarentena) e põe as datas de criação e de
    /// modificação na hora da exportação. Não segue atalhos.
    static func stripFileTraces(at url: URL, now: Date) throws {
        try removeExtendedAttributes(at: url)
        try FileManager.default.setAttributes([.creationDate: now, .modificationDate: now], ofItemAtPath: url.path)
    }

    static func removeExtendedAttributes(at url: URL) throws {
        let path = url.path
        let length = listxattr(path, nil, 0, XATTR_NOFOLLOW)
        if length < 0 {
            // Volume sem atributos estendidos: não há o que tirar.
            if errno == ENOTSUP { return }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard length > 0 else { return }
        var buffer = [CChar](repeating: 0, count: length)
        let read = listxattr(path, &buffer, length, XATTR_NOFOLLOW)
        guard read >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let names = buffer.prefix(read).split(separator: 0).map { String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
        for name in names where removexattr(path, name, XATTR_NOFOLLOW) != 0 {
            // O sistema protege alguns atributos (como `com.apple.provenance`); os outros que falharem param a exportação.
            if errno == ENOATTR || (errno == EPERM && name.hasPrefix("com.apple.provenance")) { continue }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    // MARK: JSON

    /// Mesma configuração do repositório: datas como segundos desde a data de referência, chaves ordenadas.
    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate)
        }
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            return Date(timeIntervalSinceReferenceDate: try container.decode(Double.self))
        }
        return try decoder.decode(type, from: Data(contentsOf: url))
    }
}

/// Tira de uma imagem o dono da câmera, os números de série do corpo e da lente e, sem `includeLocation`, o GPS.
enum ImagePrivacyScrubber {
    struct Failure: Error {}

    /// Caminhos dos campos no XMP/EXIF (`CGImageMetadata`) que identificam o aparelho ou a pessoa.
    private static let identifyingPaths = [
        "exif:CameraOwnerName", "exifEX:CameraOwnerName", "exifEX:BodySerialNumber", "exifEX:LensSerialNumber",
        "aux:SerialNumber", "aux:LensSerialNumber", "aux:OwnerName",
    ]
    private static var exifKeys: [CFString] {
        [kCGImagePropertyExifCameraOwnerName, kCGImagePropertyExifBodySerialNumber, kCGImagePropertyExifLensSerialNumber]
    }
    private static var auxKeys: [CFString] {
        [kCGImagePropertyExifAuxSerialNumber, kCGImagePropertyExifAuxLensSerialNumber, kCGImagePropertyExifAuxOwnerName]
    }

    /// Regrava a imagem sem os dados e devolve `true`; sem nada para tirar (ou se o ImageIO não lê o arquivo), deixa como está.
    ///
    /// Tenta primeiro copiar sem recomprimir (`CGImageDestinationCopyImageSource`), que só funciona em alguns formatos e em alguns
    /// deixa o dado para trás; a confirmação relê o resultado. Sem sucesso, regrava quadro a quadro no mesmo tipo. Se nenhum dos
    /// dois tirar tudo, lança `Failure` e o arquivo original não muda.
    /// - Parameter allowsLosslessCopy: `false` pula a cópia sem recompressão (usado para exercitar a regravação).
    @discardableResult
    static func scrub(_ url: URL, includeLocation: Bool, allowsLosslessCopy: Bool = true) throws -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(source),
            CGImageSourceGetCount(source) > 0, hasLeftovers(in: source, includeLocation: includeLocation)
        else { return false }
        let frames = CGImageSourceGetCount(source)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".share-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }

        func isClean(_ candidate: URL) -> Bool {
            guard let result = CGImageSourceCreateWithURL(candidate as CFURL, nil), CGImageSourceGetType(result) == type,
                CGImageSourceGetCount(result) == frames
            else { return false }
            return !hasLeftovers(in: result, includeLocation: includeLocation)
        }
        func install() throws {
            try FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: temporary, to: url)
        }

        if allowsLosslessCopy, copyLosslessly(source, type: type, to: temporary, includeLocation: includeLocation), isClean(temporary) {
            try install()
            return true
        }
        try? FileManager.default.removeItem(at: temporary)
        if rewrite(source, type: type, frames: frames, to: temporary, includeLocation: includeLocation), isClean(temporary) {
            try install()
            return true
        }
        throw Failure()
    }

    /// Há algo a tirar em algum quadro?
    static func hasLeftovers(in source: CGImageSource, includeLocation: Bool) -> Bool {
        for index in 0..<CGImageSourceGetCount(source) {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else { continue }
            if !includeLocation, properties[kCGImagePropertyGPSDictionary] != nil { return true }
            if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any], exifKeys.contains(where: { exif[$0] != nil }) {
                return true
            }
            if let aux = properties[kCGImagePropertyExifAuxDictionary] as? [CFString: Any], auxKeys.contains(where: { aux[$0] != nil }) {
                return true
            }
        }
        return false
    }

    private static func copyLosslessly(_ source: CGImageSource, type: CFString, to url: URL, includeLocation: Bool) -> Bool {
        guard let original = CGImageSourceCopyMetadataAtIndex(source, 0, nil), let metadata = CGImageMetadataCreateMutableCopy(original),
            let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil)
        else { return false }
        for path in identifyingPaths { CGImageMetadataRemoveTagWithPath(metadata, nil, path as CFString) }
        let options: [CFString: Any] = [kCGImageDestinationMetadata: metadata, kCGImageMetadataShouldExcludeGPS: !includeLocation]
        return CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, nil)
    }

    /// Regrava cada quadro no mesmo tipo; `kCFNull` numa propriedade a remove em vez de herdá-la da origem.
    private static func rewrite(_ source: CGImageSource, type: CFString, frames: Int, to url: URL, includeLocation: Bool) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type, frames, nil) else { return false }
        for index in 0..<frames {
            var properties = (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]) ?? [:]
            if !includeLocation, properties[kCGImagePropertyGPSDictionary] != nil { properties[kCGImagePropertyGPSDictionary] = kCFNull }
            if var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                for key in exifKeys where exif[key] != nil { exif[key] = kCFNull }
                properties[kCGImagePropertyExifDictionary] = exif
            }
            if var aux = properties[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] {
                for key in auxKeys where aux[key] != nil { aux[key] = kCFNull }
                properties[kCGImagePropertyExifAuxDictionary] = aux
            }
            CGImageDestinationAddImageFromSource(destination, source, index, properties as CFDictionary)
        }
        return CGImageDestinationFinalize(destination)
    }
}
