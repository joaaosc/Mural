import CoreGraphics
import Foundation
import ImageIO

/// Lê resolução, tamanho, perfil de cor e uma paleta simples de uma imagem.
public enum ImageInspector {
    public static func inspect(_ url: URL, paletteSize: Int = 5) -> ImageMetadata? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }

        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let profile = properties[kCGImagePropertyProfileName] as? String
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0

        let palette = Self.palette(from: source, count: paletteSize)
        return ImageMetadata(pixelWidth: width, pixelHeight: height, fileSizeBytes: size, colorProfile: profile, palette: palette)
    }

    /// Paleta por amostragem: reduz a imagem a uma grade pequena, agrupa cores
    /// parecidas e devolve as mais frequentes, ordenadas da mais clara para a mais escura.
    static func palette(from source: CGImageSource, count: Int) -> [PaletteColor] {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 48,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return [] }
        return palette(from: thumb, count: count)
    }

    public static func palette(from image: CGImage, count: Int) -> [PaletteColor] {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, count > 0 else { return [] }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let didDraw = pixels.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return false }
            // O contexto só pode usar o armazenamento enquanto o buffer é válido.
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else { return [] }

        // Agrupa em caixas de 32 níveis por canal (8 por canal = 512 caixas).
        var buckets: [Int: (sum: (Double, Double, Double), n: Int)] = [:]
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i])
            let g = Double(pixels[i + 1])
            let b = Double(pixels[i + 2])
            let key = (Int(r) / 32) << 6 | (Int(g) / 32) << 3 | (Int(b) / 32)
            let e = buckets[key] ?? ((0, 0, 0), 0)
            buckets[key] = ((e.sum.0 + r, e.sum.1 + g, e.sum.2 + b), e.n + 1)
        }
        let top = buckets.values.sorted { $0.n > $1.n }.prefix(count)
        let colors = top.map { e in
            PaletteColor(red: e.sum.0 / Double(e.n) / 255, green: e.sum.1 / Double(e.n) / 255, blue: e.sum.2 / Double(e.n) / 255)
        }
        return colors.sorted { luminance($0) > luminance($1) }
    }

    static func luminance(_ c: PaletteColor) -> Double {
        0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue
    }
}
