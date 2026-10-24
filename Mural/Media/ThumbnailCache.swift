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
    private let decodeLimiter: ThumbnailDecodeLimiter
    private var inFlight: [ThumbnailRequest: InFlight] = [:]

    init(
        loader: @escaping Loader = { request in
            await ThumbnailLoader.cgImage(
                for: request.url,
                kind: request.kind,
                maxPixelSize: request.maxPixelSize
            )
        },
        requestObserver: RequestObserver? = nil,
        decodeConcurrency: Int = 4
    ) {
        self.loader = loader
        self.requestObserver = requestObserver
        self.decodeLimiter = ThumbnailDecodeLimiter(limit: decodeConcurrency)
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
            let decodeLimiter = self.decodeLimiter
            let task = Task<CGImage?, Never> {
                guard await decodeLimiter.acquire() else { return nil }
                guard !Task.isCancelled else {
                    await decodeLimiter.release()
                    return nil
                }
                let image = await loader(request)
                await decodeLimiter.release()
                return image
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

/// Limita decodificações distintas sem bloquear threads do executor Swift.
private actor ThumbnailDecodeLimiter {
    private var available: Int
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    init(limit: Int) {
        available = max(limit, 1)
    }

    func acquire() async -> Bool {
        guard !Task.isCancelled else { return false }
        guard available == 0 else {
            available -= 1
            return true
        }

        let id = UUID()
        let acquired = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else {
                    waiters[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
        guard acquired, !Task.isCancelled else {
            if acquired { available += 1 }
            return false
        }
        return true
    }

    func release() {
        guard let (id, continuation) = waiters.first else {
            available += 1
            return
        }
        waiters.removeValue(forKey: id)
        continuation.resume(returning: true)
    }

    private func cancelWaiter(_ id: UUID) {
        guard let continuation = waiters.removeValue(forKey: id) else { return }
        continuation.resume(returning: false)
    }
}
