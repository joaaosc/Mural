import AVFoundation
import ImageIO
import MuralKit
import PDFKit

/// Gera imagens reduzidas de fotos, vídeos e PDFs fora da thread principal.
enum ThumbnailLoader {
    @concurrent
    nonisolated static func cgImage(for url: URL, kind: ItemKind, maxPixelSize: Int) async -> CGImage? {
        switch kind {
        case .image:
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        case .video:
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
            return try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        case .pdf:
            guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let scale = CGFloat(maxPixelSize) / max(bounds.width, bounds.height, 1)
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            return page.thumbnail(of: size, for: .mediaBox).cgImage(forProposedRect: nil, context: nil, hints: nil)
        case .text, .checklist, .sticky, .link, .folder:
            return nil
        }
    }
}
