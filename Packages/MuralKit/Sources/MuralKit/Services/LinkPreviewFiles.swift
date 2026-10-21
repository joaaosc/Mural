import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Guarda as imagens e os ícones das prévias de link, já reduzidos, numa pasta própria (fora da pasta de itens).
///
/// Cada gravação cria arquivos com nomes novos, então um arquivo nunca é sobrescrito: o cartão passa a
/// apontar para o nome novo e o antigo é apagado depois por `sweep(keeping:minimumAge:now:)`.
public struct LinkPreviewFiles: Sendable {
    /// Maior lado da imagem de prévia, em pixels.
    private static let maximumImageSide = 800
    /// Menor lado aceito numa imagem de prévia; abaixo disso é provável pixel de rastreamento.
    private static let minimumImageSide = 32
    /// Maior lado do ícone, em pixels.
    private static let maximumIconSide = 64
    /// Menor lado aceito num ícone.
    private static let minimumIconSide = 16
    private static let jpegQuality = 0.82
    /// Imagens com mais pixels que isto são recusadas sem decodificar, para uma imagem minúscula no arquivo
    /// mas gigante na tela não esgotar a memória.
    private static let maximumSourcePixels = 100_000_000

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Endereço do arquivo com esse nome dentro da pasta.
    public func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }

    /// Reduz e grava a imagem de prévia e o ícone de um cartão, criando a pasta se faltar.
    ///
    /// A imagem sai com no máximo 800 px no lado maior, em JPEG (qualidade 0,82) ou, se tiver transparência,
    /// em PNG. O ícone sai com no máximo 64 px, sempre em PNG. A orientação da foto é aplicada. Dados que não
    /// sejam imagem, imagem com lado menor que 32 px (ícone: 16 px) ou grande demais viram `nil`, sem erro.
    /// Os nomes são `<itemID>-<8 hex>.jpg|png` e `<itemID>-icon-<8 hex>.png`, novos a cada chamada.
    /// - Throws: erro de disco ao criar a pasta ou gravar. O que já tiver sido gravado nesta chamada fica na
    ///   pasta, sem cartão que o use, até o próximo `sweep(keeping:minimumAge:now:)`.
    public func store(imageData: Data?, iconData: Data?, for itemID: UUID) throws -> (image: String?, icon: String?) {
        let image = imageData.flatMap {
            Self.reduced($0, maximumSide: Self.maximumImageSide, minimumSide: Self.minimumImageSide, allowsJPEG: true)
        }
        let icon = iconData.flatMap {
            Self.reduced($0, maximumSide: Self.maximumIconSide, minimumSide: Self.minimumIconSide, allowsJPEG: false)
        }
        guard image != nil || icon != nil else { return (nil, nil) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var names: (image: String?, icon: String?) = (nil, nil)
        if let image {
            let name = uniqueName(itemID: itemID, kind: "", fileExtension: image.fileExtension)
            try image.data.write(to: url(for: name), options: .atomic)
            names.image = name
        }
        if let icon {
            let name = uniqueName(itemID: itemID, kind: "icon-", fileExtension: icon.fileExtension)
            try icon.data.write(to: url(for: name), options: .atomic)
            names.icon = name
        }
        return names
    }

    /// Apaga os arquivos da pasta que nenhum cartão usa e que são mais antigos que `minimumAge`.
    ///
    /// A idade mínima protege arquivos recém-gravados, que ainda não chegaram ao cartão. Subpastas e arquivos
    /// ocultos não são tocados, e uma pasta que não existe não é erro.
    /// - Parameter referenced: nomes em uso (`BoardModel.referencedLinkPreviewFiles`).
    /// - Returns: os nomes apagados, em ordem alfabética.
    @discardableResult
    public func sweep(keeping referenced: Set<String>, minimumAge: TimeInterval = 600, now: Date = .now) -> [String] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return [] }

        var removed: [String] = []
        for url in urls {
            let name = url.lastPathComponent
            guard !referenced.contains(name),
                let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                let modified = values.contentModificationDate, now.timeIntervalSince(modified) > minimumAge,
                (try? FileManager.default.removeItem(at: url)) != nil
            else { continue }
            removed.append(name)
        }
        return removed.sorted()
    }

    // MARK: Nomes

    /// `<itemID>-<8 hex>` com o `kind` entre os dois; se o nome já existir, sorteia de novo.
    private func uniqueName(itemID: UUID, kind: String, fileExtension: String) -> String {
        var name = ""
        for _ in 0..<16 {
            name = "\(itemID.uuidString)-\(kind)\(UUID().uuidString.prefix(8)).\(fileExtension)"
            if !FileManager.default.fileExists(atPath: url(for: name).path) { break }
        }
        return name
    }

    // MARK: Imagem

    /// Reduz a imagem e a codifica; `nil` se os dados não forem uma imagem aceita.
    private static func reduced(
        _ data: Data, maximumSide: Int, minimumSide: Int, allowsJPEG: Bool
    ) -> (data: Data, fileExtension: String)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
            CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
            min(width, height) >= minimumSide
        else { return nil }
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, pixels <= maximumSourcePixels else { return nil }

        // A miniatura nunca amplia: uma imagem menor que o limite sai no tamanho original.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumSide,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
            let bitmap = rendered(thumbnail)
        else { return nil }

        if allowsJPEG, bitmap.isOpaque, let jpeg = encode(bitmap.image, as: .jpeg, quality: jpegQuality) {
            return (jpeg, "jpg")
        }
        return encode(bitmap.image, as: .png, quality: nil).map { ($0, "png") }
    }

    /// Redesenha a imagem em RGBA 8 bits sRGB e informa se algum pixel é transparente. Um PNG com canal alfa
    /// todo opaco (o mais comum em capturas de tela) conta como opaco.
    private static func rendered(_ image: CGImage) -> (image: CGImage, isOpaque: Bool)? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let pixels = context.data
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let bytes = pixels.assumingMemoryBound(to: UInt8.self)
        var isOpaque = true
        scan: for row in 0..<height {
            let start = row * context.bytesPerRow
            for column in 0..<width where bytes[start + column * 4 + 3] != 255 {
                isOpaque = false
                break scan
            }
        }
        return context.makeImage().map { ($0, isOpaque) }
    }

    private static func encode(_ image: CGImage, as type: UTType, quality: Double?) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, type.identifier as CFString, 1, nil) else {
            return nil
        }
        var properties: [CFString: Any] = [:]
        if let quality { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
