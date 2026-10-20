import CoreGraphics
import SwiftUI
import Testing

@testable import Mural

/// Esmaecer um cartão não pode deixar ver o que está atrás dele.
@MainActor
struct CardEmphasisTests {
    @Test("Cartão esmaecido esconde o cartão que está atrás dele")
    func dimmedCardHidesCardBehind() throws {
        let pixel = try Self.centerPixel {
            ZStack {
                Color.red
                Color.gray.cardEmphasis(0.3)
            }
        }
        #expect(pixel.isNeutral, "o vermelho de trás atravessou o cartão: \(pixel)")
    }

    @Test("Pasta esmaecida esconde a mídia guardada atrás da própria folha")
    func dimmedFolderHidesItsOwnMedia() throws {
        let pixel = try Self.centerPixel {
            ZStack {
                Color.red
                Color.gray
            }
            .cardEmphasis(0.3)
        }
        #expect(pixel.isNeutral, "a mídia de trás atravessou a folha: \(pixel)")
    }

    @Test("Controle: a opacidade comum deixaria o cartão de trás aparecer")
    func plainOpacityLetsCardBehindShow() throws {
        let pixel = try Self.centerPixel {
            ZStack {
                Color.red
                Color.gray.opacity(0.3)
            }
        }
        #expect(!pixel.isNeutral, "a leitura do pixel deveria notar o vermelho: \(pixel)")
    }

    @Test("Destaque total deixa o cartão como está")
    func fullEmphasisKeepsCard() throws {
        let pixel = try Self.centerPixel { Color(red: 0.2, green: 0.4, blue: 0.6).cardEmphasis(1) }
        #expect(abs(pixel.red - 0.2) < 0.02)
        #expect(abs(pixel.green - 0.4) < 0.02)
        #expect(abs(pixel.blue - 0.6) < 0.02)
        #expect(pixel.alpha == 1)
    }

    struct Pixel: CustomStringConvertible {
        var red: Double
        var green: Double
        var blue: Double
        var alpha: Double

        /// Cinza: sem puxar para o vermelho do que estava atrás.
        var isNeutral: Bool { abs(red - blue) < 0.03 && abs(red - green) < 0.03 }

        var description: String {
            String(format: "r %.2f g %.2f b %.2f a %.2f", red, green, blue, alpha)
        }
    }

    /// Desenha a view num quadrado de 40 pontos e lê a cor do pixel central.
    static func centerPixel(@ViewBuilder _ content: () -> some View) throws -> Pixel {
        let renderer = ImageRenderer(content: content().frame(width: 40, height: 40))
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
            context.draw(image, in: CGRect(x: -20, y: -20, width: image.width, height: image.height))
            return true
        }
        try #require(drawn)
        return Pixel(
            red: Double(bytes[0]) / 255, green: Double(bytes[1]) / 255, blue: Double(bytes[2]) / 255,
            alpha: Double(bytes[3]) / 255)
    }
}
