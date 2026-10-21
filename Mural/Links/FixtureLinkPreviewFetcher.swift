import CoreGraphics
import Foundation
import ImageIO
import MuralKit
import UniformTypeIdentifiers

/// Buscador dos testes de interface: não usa a rede e devolve sempre a mesma página de exemplo, com uma
/// imagem e um ícone desenhados na hora.
nonisolated struct FixtureLinkPreviewFetcher: LinkPreviewFetching {
    func fetchPreview(for request: LinkPreviewRequest) async throws -> FetchedLinkPreview {
        FetchedLinkPreview(
            title: "Página de exemplo", siteName: "Exemplo", summary: "Resumo de teste do Mural.",
            imageData: Self.png(width: 640, height: 335, color: (0.2, 0.5, 0.8)),
            iconData: Self.png(width: 64, height: 64, color: (0.9, 0.3, 0.1)))
    }

    /// PNG opaco de uma cor, com um retângulo mais claro no canto.
    private static func png(width: Int, height: Int, color: (red: Double, green: Double, blue: Double)) -> Data? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.35)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))

        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
