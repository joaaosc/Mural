import CoreGraphics
import Testing

@testable import MuralKit

struct ImageInspectorTests {
    @Test("Paleta preserva as cores desenhadas no buffer")
    func extractsKnownColors() throws {
        let image = try makeImage()
        let colors = ImageInspector.palette(from: image, count: 5)
        #expect(colors.count == 2)
        #expect(colors[0].red > 0.99 && colors[0].green > 0.99 && colors[0].blue > 0.99)
        #expect(colors[1].red > 0.99 && colors[1].green < 0.01 && colors[1].blue < 0.01)
    }

    @Test("Contagem não positiva não produz paleta", arguments: [0, -1, Int.min])
    func rejectsInvalidCount(_ count: Int) throws {
        #expect(ImageInspector.palette(from: try makeImage(), count: count).isEmpty)
    }

    private func makeImage() throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 16,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 2))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        return try #require(context.makeImage())
    }
}
