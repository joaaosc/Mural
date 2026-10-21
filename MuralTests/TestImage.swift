import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

/// Imagens geradas em memória pelos testes: nenhum arquivo de mídia é versionado.
enum TestImage {
    /// PNG opaco de `width` × `height`; tamanhos diferentes dão bytes diferentes.
    static func png(width: Int, height: Int) throws -> Data {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 0.9, green: 0.3, blue: 0.1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        let image = try #require(context.makeImage())

        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        return output as Data
    }

    /// O PNG seguido de zeros até ter exatamente `count` bytes. O ImageIO ainda o lê: o que vem depois do
    /// fim do PNG é ignorado.
    static func png(width: Int, height: Int, paddedTo count: Int) throws -> Data {
        var data = try png(width: width, height: height)
        try #require(data.count <= count, "o PNG já passa de \(count) bytes")
        data.append(Data(count: count - data.count))
        return data
    }
}
