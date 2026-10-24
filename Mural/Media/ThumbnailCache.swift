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
        var waiters: Set<UUID>
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
        guard !Task.isCancelled else { return nil }
        if let cached = cachedImage(for: request) { return cached }

        let waiterID = UUID()
        let entry: InFlight
        if var existing = inFlight[request] {
            existing.waiters.insert(waiterID)
            inFlight[request] = existing
            entry = existing
        } else {
            let loader = self.loader
            let task = Task {
                await loader(request)
            }
            let newEntry = InFlight(id: UUID(), task: task, waiters: [waiterID])
            inFlight[request] = newEntry
            entry = newEntry
        }

        defer {
            releaseWaiter(waiterID, for: request, entryID: entry.id, cancelIfLast: Task.isCancelled)
        }

        let image = await withTaskCancellationHandler {
            await entry.task.value
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.releaseWaiter(waiterID, for: request, entryID: entry.id, cancelIfLast: true)
            }
        }
        guard !Task.isCancelled, inFlight[request]?.id == entry.id, let image else { return nil }
        images.setObject(image, forKey: key(request), cost: image.bytesPerRow * image.height)
        return image
    }

    /// Descarta uma miniatura pronta e impede uma geração antiga do mesmo pedido de repovoar o cache.
    func invalidate(_ request: ThumbnailRequest) {
        images.removeObject(forKey: key(request))
        guard let entry = inFlight.removeValue(forKey: request) else { return }
        entry.task.cancel()
    }

    private func releaseWaiter(
        _ waiterID: UUID,
        for request: ThumbnailRequest,
        entryID: UUID,
        cancelIfLast: Bool
    ) {
        guard var entry = inFlight[request], entry.id == entryID, entry.waiters.remove(waiterID) != nil else { return }
        guard entry.waiters.isEmpty else {
            inFlight[request] = entry
            return
        }

        inFlight.removeValue(forKey: request)
        if cancelIfLast { entry.task.cancel() }
    }

    private func key(_ request: ThumbnailRequest) -> NSString {
        "\(request.url.absoluteString)#\(request.kind.rawValue)#\(request.maxPixelSize)" as NSString
    }
}
