import AVFoundation
import ImageIO
import MuralKit
import PDFKit
import os

/// Gera imagens reduzidas de fotos, vídeos e PDFs fora da thread principal.
enum ThumbnailLoader {
    @concurrent
    nonisolated static func cgImage(for url: URL, kind: ItemKind, maxPixelSize: Int) async -> CGImage? {
        let signpost = MuralSignposts.media.beginInterval("Decodificar miniatura")
        defer { MuralSignposts.media.endInterval("Decodificar miniatura", signpost) }
        guard maxPixelSize > 0, !Task.isCancelled else { return nil }

        let image: CGImage?
        switch kind {
        case .image:
            guard
                let source = CGImageSourceCreateWithURL(
                    url as CFURL,
                    [kCGImageSourceShouldCache: false] as CFDictionary
                )
            else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        case .video:
            let generator = CancellableVideoThumbnailGenerator(url: url, maxPixelSize: maxPixelSize)
            image = await withTaskCancellationHandler {
                guard !Task.isCancelled else { return nil }
                return await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600))
            } onCancel: {
                generator.cancel()
            }
        case .pdf:
            guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let scale = CGFloat(maxPixelSize) / max(bounds.width, bounds.height, 1)
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            image = page.thumbnail(of: size, for: .mediaBox).cgImage(forProposedRect: nil, context: nil, hints: nil)
        case .text, .checklist, .sticky, .link, .reminder, .music, .folder:
            return nil
        }
        return Task.isCancelled ? nil : image
    }
}

/// Encapsula a geração de vídeo para que o cancelamento do consumidor também pare o trabalho nativo.
/// O SDK não declara `AVAssetImageGenerator` como `Sendable`; o acesso fica limitado ao ciclo de
/// uma única geração, e a operação de cancelamento usa a API nativa para pedidos pendentes.
private final class CancellableVideoThumbnailGenerator: @unchecked Sendable {
    private nonisolated(unsafe) let generator: AVAssetImageGenerator

    nonisolated init(url: URL, maxPixelSize: Int) {
        generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
    }

    nonisolated func image(at time: CMTime) async -> CGImage? {
        try? await generator.image(at: time).image
    }

    nonisolated func cancel() {
        generator.cancelAllCGImageGeneration()
    }
}
