import CoreGraphics
import Foundation
import MuralKit

/// Guarda as miniaturas já geradas, com teto de memória: o sistema descarta as mais
/// antigas quando o teto é atingido ou quando a memória do Mac fica apertada.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    typealias Loader = @Sendable (ThumbnailRequest) async -> CGImage?
    typealias RequestObserver = @MainActor (ThumbnailRequest) -> Void

    private struct InFlight {
        let id: UUID
        let task: Task<CGImage?, Never>
    }

    private let images = NSCache<NSString, CGImage>()
    private let loader: Loader
    private let requestObserver: RequestObserver?
    private var inFlight: [ThumbnailRequest: InFlight] = [:]

    init(
        loader: @escaping Loader = { request in
            await ThumbnailLoader.cgImage(
                for: request.url,
                kind: request.kind,
                maxPixelSize: request.maxPixelSize
            )
        },
        requestObserver: RequestObserver? = nil
    ) {
        self.loader = loader
        self.requestObserver = requestObserver
        images.totalCostLimit = 256 * 1024 * 1024
    }

    /// Miniatura já pronta, sem esperar: evita o quadro cinza quando um cartão reaparece.
    func cachedImage(for request: ThumbnailRequest) -> CGImage? {
        images.object(forKey: key(request))
    }

    func image(for request: ThumbnailRequest) async -> CGImage? {
        requestObserver?(request)
        if let cached = cachedImage(for: request) { return cached }

        let entry: InFlight
        if let existing = inFlight[request] {
            entry = existing
        } else {
            let loader = self.loader
            let task = Task {
                await loader(request)
            }
            let newEntry = InFlight(id: UUID(), task: task)
            inFlight[request] = newEntry
            entry = newEntry
        }

        defer {
            if inFlight[request]?.id == entry.id {
                inFlight.removeValue(forKey: request)
            }
        }

        guard let image = await entry.task.value else { return nil }
        images.setObject(image, forKey: key(request), cost: image.bytesPerRow * image.height)
        return image
    }

    private func key(_ request: ThumbnailRequest) -> NSString {
        "\(request.url.absoluteString)#\(request.kind.rawValue)#\(request.maxPixelSize)" as NSString
    }
}
