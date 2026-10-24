import CoreGraphics
import Foundation
import MuralKit
import Testing

@testable import Mural

@MainActor
struct ThumbnailCacheTests {
    @Test("Um cache hit não executa o loader novamente")
    func cachedImageIsReused() async {
        let recorder = ThumbnailRequestRecorder(result: makeImage(width: 2))
        let cache = ThumbnailCache(loader: { request in
            await recorder.load(request)
        })
        let url = URL(filePath: "/tmp/photo.jpg")
        let imageRequest = ThumbnailRequest(url: url, kind: .image, maxPixelSize: 640)

        let loaded = await cache.image(for: imageRequest)
        let cached = await cache.image(for: imageRequest)

        #expect(loaded?.width == 2)
        #expect(cached?.width == 2)
        #expect(cache.cachedImage(for: imageRequest)?.width == 2)
        #expect(await recorder.count == 1)
    }

    @Test("A chave da miniatura inclui URL, tipo e tamanho")
    func requestIdentitySeparatesEntries() async {
        let recorder = ThumbnailRequestRecorder(result: makeImage(width: 2))
        let cache = ThumbnailCache(loader: { request in
            await recorder.load(request)
        })
        let url = URL(filePath: "/tmp/photo.jpg")

        _ = await cache.image(
            for: ThumbnailRequest(
                url: URL(filePath: "/tmp/other-photo.jpg"),
                kind: .image,
                maxPixelSize: 640
            )
        )
        _ = await cache.image(for: ThumbnailRequest(url: url, kind: .video, maxPixelSize: 640))
        _ = await cache.image(for: ThumbnailRequest(url: url, kind: .image, maxPixelSize: 1280))

        #expect(await recorder.count == 3)
    }

    @Test("Gerações concorrentes do mesmo pedido compartilham o loader")
    func concurrentRequestsAreCoalesced() async {
        let recorder = ThumbnailRequestRecorder(result: makeImage(width: 3), waitsForRelease: true)
        let observer = ThumbnailRequestObserver()
        let cache = ThumbnailCache(
            loader: { request in
                await recorder.load(request)
            }, requestObserver: observer.observe)
        let request = ThumbnailRequest(
            url: URL(filePath: "/tmp/photo.jpg"),
            kind: .image,
            maxPixelSize: 640
        )

        let first = Task { await cache.image(for: request) }
        await observer.waitForCount(1)
        let second = Task { await cache.image(for: request) }
        await observer.waitForCount(2)
        await recorder.release()

        let firstImage = await first.value
        let secondImage = await second.value

        #expect(firstImage?.width == 3)
        #expect(secondImage?.width == 3)
        #expect(await recorder.count == 1)
    }

    @Test("Cancelar um waiter não cancela a geração compartilhada")
    func cancellingOneWaiterDoesNotCancelTheSharedLoad() async {
        let recorder = ThumbnailRequestRecorder(result: makeImage(width: 4), waitsForRelease: true)
        let observer = ThumbnailRequestObserver()
        let cache = ThumbnailCache(
            loader: { request in
                await recorder.load(request)
            }, requestObserver: observer.observe)
        let request = ThumbnailRequest(
            url: URL(filePath: "/tmp/photo.jpg"),
            kind: .image,
            maxPixelSize: 640
        )

        let cancelledWaiter = Task { await cache.image(for: request) }
        await observer.waitForCount(1)
        let survivingWaiter = Task { await cache.image(for: request) }
        await observer.waitForCount(2)

        cancelledWaiter.cancel()
        await recorder.release()

        let survivingImage = await survivingWaiter.value
        let cancelledImage = await cancelledWaiter.value

        #expect(survivingImage?.width == 4)
        #expect(cancelledImage == nil)
        #expect(await recorder.count == 1)
        #expect(await recorder.cancellationCount == 0)
    }

    @Test("Cancelar o último waiter cancela a geração e permite nova tentativa")
    func cancellingLastWaiterCancelsTheLoad() async {
        let loader = CancellableThumbnailLoader(retryResult: makeImage(width: 5))
        let observer = ThumbnailRequestObserver()
        let cache = ThumbnailCache(
            loader: { request in
                await loader.load(request)
            }, requestObserver: observer.observe)
        let request = ThumbnailRequest(
            url: URL(filePath: "/tmp/photo.jpg"),
            kind: .image,
            maxPixelSize: 640
        )

        let cancelledWaiter = Task { await cache.image(for: request) }
        await observer.waitForCount(1)
        cancelledWaiter.cancel()
        await loader.waitForCancellation()

        #expect(await cancelledWaiter.value == nil)
        #expect(await cache.image(for: request)?.width == 5)
        #expect(await loader.count == 2)
    }

    @Test("Falhas não ficam armazenadas como cache permanente")
    func failedLoadsAreRetried() async {
        let recorder = ThumbnailRequestRecorder(result: nil)
        let cache = ThumbnailCache(loader: { request in
            await recorder.load(request)
        })
        let request = ThumbnailRequest(
            url: URL(filePath: "/tmp/missing.jpg"),
            kind: .image,
            maxPixelSize: 640
        )

        #expect(await cache.image(for: request) == nil)
        #expect(await cache.image(for: request) == nil)
        #expect(await recorder.count == 2)
    }

    @Test("Invalidar descarta o cache e bloqueia resultado antigo em voo")
    func invalidationPreventsStaleRepopulation() async {
        let recorder = ThumbnailRequestRecorder(result: makeImage(width: 6), waitsForRelease: true)
        let observer = ThumbnailRequestObserver()
        let cache = ThumbnailCache(
            loader: { request in
                await recorder.load(request)
            }, requestObserver: observer.observe)
        let request = ThumbnailRequest(
            url: URL(filePath: "/tmp/replaced.jpg"),
            kind: .image,
            maxPixelSize: 640
        )

        let staleLoad = Task { await cache.image(for: request) }
        await observer.waitForCount(1)
        cache.invalidate(request)
        await recorder.release()

        #expect(await staleLoad.value == nil)
        #expect(cache.cachedImage(for: request) == nil)
        #expect(await cache.image(for: request)?.width == 6)
        #expect(await recorder.count == 2)
    }
}

@MainActor
private final class ThumbnailRequestObserver {
    private var requests: [ThumbnailRequest] = []
    private var continuation: CheckedContinuation<Void, Never>?
    private var expectedCount: Int?

    func observe(_ request: ThumbnailRequest) {
        requests.append(request)
        if let expectedCount, requests.count >= expectedCount {
            continuation?.resume()
            continuation = nil
            self.expectedCount = nil
        }
    }

    func waitForCount(_ expected: Int) async {
        guard requests.count < expected else { return }
        expectedCount = expected
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }
}

private actor ThumbnailRequestRecorder {
    private let result: CGImage?
    private let waitsForRelease: Bool
    private(set) var count = 0
    private(set) var cancellationCount = 0
    private var releaseContinuations: [CheckedContinuation<CGImage?, Never>] = []
    private var released = false

    init(result: CGImage?, waitsForRelease: Bool = false) {
        self.result = result
        self.waitsForRelease = waitsForRelease
    }

    func load(_: ThumbnailRequest) async -> CGImage? {
        count += 1
        guard waitsForRelease, !released else { return result }

        let loaded = await withCheckedContinuation { continuation in
            releaseContinuations.append(continuation)
        }
        if Task.isCancelled { cancellationCount += 1 }
        return loaded
    }

    func release() {
        released = true
        let continuations = releaseContinuations
        releaseContinuations.removeAll()
        for continuation in continuations {
            continuation.resume(returning: result)
        }
    }
}

private actor CancellableThumbnailLoader {
    private let retryResult: CGImage
    private(set) var count = 0
    private var cancellationContinuations: [CheckedContinuation<Void, Never>] = []
    private var didObserveCancellation = false

    init(retryResult: CGImage) {
        self.retryResult = retryResult
    }

    func load(_: ThumbnailRequest) async -> CGImage? {
        count += 1
        guard count == 1 else { return retryResult }

        while !Task.isCancelled {
            await Task.yield()
        }
        didObserveCancellation = true
        let continuations = cancellationContinuations
        cancellationContinuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
        return nil
    }

    func waitForCancellation() async {
        guard !didObserveCancellation else { return }
        await withCheckedContinuation { continuation in
            cancellationContinuations.append(continuation)
        }
    }
}

private func makeImage(width: Int) -> CGImage {
    let bytes = Data(repeating: 0xFF, count: width * 4)
    guard let provider = CGDataProvider(data: bytes as CFData),
        let image = CGImage(
            width: width,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    else {
        fatalError("Não foi possível criar a imagem de teste")
    }
    return image
}
