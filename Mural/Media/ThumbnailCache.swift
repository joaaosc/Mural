import CoreGraphics
import Foundation
import MuralKit

/// Guarda as miniaturas já geradas, com teto de memória: o sistema descarta as mais
/// antigas quando o teto é atingido ou quando a memória do Mac fica apertada.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let images = NSCache<NSString, CGImage>()

    private init() {
        images.totalCostLimit = 256 * 1024 * 1024
    }

    func image(for url: URL, kind: ItemKind, maxPixelSize: Int) async -> CGImage? {
        let key = "\(url.path)#\(maxPixelSize)" as NSString
        if let cached = images.object(forKey: key) { return cached }
        guard let image = await ThumbnailLoader.cgImage(for: url, kind: kind, maxPixelSize: maxPixelSize) else { return nil }
        images.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }
}
