import SwiftUI
import Testing

@testable import Mural

/// Encolher o cartão sobre a pasta: renderiza o efeito de verdade, com o shader, e mede os pixels.
@MainActor
struct FolderHoverShrinkTests {
    private let cardSize = CGSize(width: 150, height: 190)

    /// Pixels não transparentes e a caixa que os contém, em pontos (escala 1).
    private func opaqueBounds(progress: Double) throws -> (count: Int, box: CGRect) {
        let view = Color.orange
            .frame(width: cardSize.width, height: cardSize.height)
            .modifier(
                FolderHoverShrink(
                    progress: progress,
                    anchor: CGPoint(x: cardSize.width / 2, y: cardSize.height / 2),
                    minScale: FolderHoverShrink.minScale(for: cardSize),
                    size: cardSize, reduceMotion: false))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(
            CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var count = 0
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 8 {
                count += 1
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard count > 0 else { return (0, .zero) }
        return (count, CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }

    @Test("A escala mínima deixa o lado maior em 72 pt, e cartões menores não mudam")
    func minScaleKeepsTheLongestSideAtTheMinimum() {
        let scale = FolderHoverShrink.minScale(for: cardSize)
        #expect(abs(cardSize.height * scale - 72) < 0.001)
        #expect(FolderHoverShrink.minScale(for: CGSize(width: 60, height: 70)) == 1)
    }

    @Test("Em qualquer ponto da transição o cartão continua visível")
    func cardStaysVisibleThroughTheTransition() throws {
        for progress in [0.0, 0.5, 1.0] {
            let result = try opaqueBounds(progress: progress)
            #expect(result.count > 0, "progresso \(progress)")
        }
    }

    @Test("Encolhido, o lado maior do cartão não passa de 72 pt")
    func shrunkCardFitsTheMinimumSize() throws {
        let full = try opaqueBounds(progress: 0)
        #expect(full.box.height >= cardSize.height - 1)

        let shrunk = try opaqueBounds(progress: 1)
        #expect(max(shrunk.box.width, shrunk.box.height) <= 72 + 2)
        #expect(shrunk.count < full.count)
    }
}
