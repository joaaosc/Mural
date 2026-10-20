import CoreGraphics
import SwiftUI
import Testing

/// Cor de um pixel de uma view desenhada fora da tela (sRGB, alfa pré-multiplicado, 0 a 1).
struct RenderedPixel: CustomStringConvertible {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    /// Cinza: sem puxar para a cor de algo que estava atrás.
    var isNeutral: Bool { abs(red - blue) < 0.03 && abs(red - green) < 0.03 }

    var description: String {
        String(format: "r %.2f g %.2f b %.2f a %.2f", red, green, blue, alpha)
    }

    /// Desenha `content` no tamanho dado, um pixel por ponto, e lê o pixel em `point`
    /// (contado a partir do canto superior esquerdo).
    @MainActor
    static func read(_ content: some View, size: CGSize, at point: CGPoint) throws -> RenderedPixel {
        let renderer = ImageRenderer(content: content.frame(width: size.width, height: size.height))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var bytes = [UInt8](repeating: 0, count: 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            // O CGContext conta de baixo para cima: a imagem é deslocada para o pixel pedido cair em (0, 0).
            let height = CGFloat(image.height)
            context.draw(image, in: CGRect(x: -point.x, y: point.y + 1 - height, width: CGFloat(image.width), height: height))
            return true
        }
        try #require(drawn)
        return RenderedPixel(
            red: Double(bytes[0]) / 255, green: Double(bytes[1]) / 255, blue: Double(bytes[2]) / 255,
            alpha: Double(bytes[3]) / 255)
    }
}
