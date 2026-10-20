import CoreGraphics
import Foundation
import MuralKit
import Testing

@testable import Mural

@MainActor
struct ThumbnailCacheTests {
    @Test("A chave da miniatura inclui URL, tipo e tamanho")
    func requestIdentitySeparatesEntries() async {
        let recorder = ThumbnailRequestRecorder(result: makeImage(width: 2))
        let cache = ThumbnailCache(loader: { request in
            await recorder.load(request)
        })
        let url = URL(filePath: "/tmp/photo.jpg")
        let imageRequest = ThumbnailRequest(url: url, kind: .image, maxPixelSize: 640)

        _ = await cache.image(for: imageRequest)
        _ = await cache.image(for: imageRequest)
        _ = await cache.image(
            for: ThumbnailRequest(
                url: URL(filePath: "/tmp/other-photo.jpg"),
                kind: .image,
                maxPixelSize: 640
            )
        )
        _ = await cache.image(for: ThumbnailRequest(url: url, kind: .video, maxPixelSize: 640))
        _ = await cache.image(for: ThumbnailRequest(url: url, kind: .image, maxPixelSize: 1280))

        #expect(await recorder.count == 4)
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
        _ = await cancelledWaiter.value

        #expect(survivingImage?.width == 4)
        #expect(await recorder.count == 1)
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
    private var releaseContinuations: [CheckedContinuation<CGImage?, Never>] = []
    private var released = false

    init(result: CGImage?, waitsForRelease: Bool = false) {
        self.result = result
        self.waitsForRelease = waitsForRelease
    }

    func load(_: ThumbnailRequest) async -> CGImage? {
        count += 1
        guard waitsForRelease, !released else { return result }

        return await withCheckedContinuation { continuation in
            releaseContinuations.append(continuation)
        }
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
