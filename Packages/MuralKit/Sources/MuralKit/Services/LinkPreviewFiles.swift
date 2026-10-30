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
    /// mas gigante na tela não esgotar a memória. A fila grava até 4 imagens ao mesmo tempo: com 40 milhões de
    /// pixels (uns 160 MB em RGBA) o pico fica abaixo de 1 GB; com os 100 milhões de antes (uns 400 MB), passava de 1,5 GB.
    static let maximumSourcePixels = 40_000_000

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Endereço do arquivo com esse nome dentro da pasta; `nil` se o nome não for seguro.
    ///
    /// Os nomes vêm do `board.json`, que pode ter vindo de um pacote importado, então só vale um nome simples,
    /// que não saia da pasta: ficam de fora o nome vazio, o que contém `/`, `\` ou `..` e o que começa por `.`.
    public func url(for fileName: String) -> URL? {
        Self.isSafeFileName(fileName) ? fileURL(named: fileName) : nil
    }

    /// Endereço do arquivo com esse nome, se o nome for seguro (ver `url(for:)`) e o arquivo existir na pasta.
    ///
    /// Um nome que aponta para uma subpasta não conta. Serve para mostrar a imagem só quando ela está lá: a
    /// pasta das prévias de um mural pode não acompanhá-lo (rascunho promovido, pacote importado).
    public func existingURL(for fileName: String) -> URL? {
        guard let url = url(for: fileName) else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return nil }
        return url
    }

    /// Os dados são uma imagem que `store(imageData:iconData:for:)` aceitaria como imagem de prévia: um formato
    /// que o ImageIO lê, com lado menor de 32 px ou mais e até 40 milhões de pixels. Só o cabeçalho é lido.
    public static func canStoreImage(_ data: Data) -> Bool {
        acceptedSource(of: data, minimumSide: minimumImageSide) != nil
    }

    /// O mesmo para o ícone, cujo lado menor mínimo é 16 px.
    public static func canStoreIcon(_ data: Data) -> Bool {
        acceptedSource(of: data, minimumSide: minimumIconSide) != nil
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
            try image.data.write(to: fileURL(named: name), options: .atomic)
            names.image = name
        }
        if let icon {
            let name = uniqueName(itemID: itemID, kind: "icon-", fileExtension: icon.fileExtension)
            try icon.data.write(to: fileURL(named: name), options: .atomic)
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

    /// Maior tamanho de um arquivo de prévia dentro de uma cópia para outras pessoas (`Previews/`).
    static let maximumEmbeddedBytes = 2 * 1024 * 1024

    /// O arquivo cabe numa cópia para outras pessoas: comum (não atalho), até `maximumEmbeddedBytes`, uma imagem que o ImageIO
    /// lê e com no máximo `maximumSourcePixels`. Só o cabeçalho da imagem é lido. A exportação e a validação do pacote usam esta
    /// mesma regra, para a exportação nunca produzir o que a importação recusaria.
    static func isEmbeddable(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
            values.isSymbolicLink != true, values.isRegularFile == true, let size = values.fileSize, size <= maximumEmbeddedBytes,
            let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { return false }
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        return !overflow && pixels <= maximumSourcePixels
    }

    // MARK: Nomes

    /// Endereço de um arquivo da pasta sem conferir o nome: só para os nomes que esta própria estrutura gera.
    private func fileURL(named name: String) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    /// Nome simples de arquivo: não vazio, sem `/`, `\` nem `..` e sem começar por `.`.
    static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".") && !name.contains("/") && !name.contains("\\") && !name.contains("..")
    }

    /// `<itemID>-<8 hex>` com o `kind` entre os dois; se o nome já existir, sorteia de novo.
    private func uniqueName(itemID: UUID, kind: String, fileExtension: String) -> String {
        var name = ""
        for _ in 0..<16 {
            name = "\(itemID.uuidString)-\(kind)\(UUID().uuidString.prefix(8)).\(fileExtension)"
            if !FileManager.default.fileExists(atPath: fileURL(named: name).path) { break }
        }
        return name
    }

    // MARK: Imagem

    /// A origem da imagem, se o cabeçalho a aceita: lado menor de ao menos `minimumSide` e até o teto de pixels.
    /// Não decodifica os pixels.
    private static func acceptedSource(of data: Data, minimumSide: Int) -> CGImageSource? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
            CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
            min(width, height) >= minimumSide
        else { return nil }
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        return !overflow && pixels <= maximumSourcePixels ? source : nil
    }

    /// Reduz a imagem e a codifica; `nil` se os dados não forem uma imagem aceita.
    private static func reduced(
        _ data: Data, maximumSide: Int, minimumSide: Int, allowsJPEG: Bool
    ) -> (data: Data, fileExtension: String)? {
        guard let source = acceptedSource(of: data, minimumSide: minimumSide) else { return nil }

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
