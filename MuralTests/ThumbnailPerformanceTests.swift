import CoreGraphics
import Foundation
import ImageIO
import MuralKit
import UniformTypeIdentifiers
import XCTest

@testable import Mural

final class ThumbnailPerformanceTests: XCTestCase {
    func testImageThumbnailGenerationPerformance() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThumbnailPerformanceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let sourceURL = temporaryDirectory.appendingPathComponent("fixture.png")
        try makeDeterministicPNG(at: sourceURL, width: 2048, height: 1536)

        let result = LockedThumbnailResult()
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let expectation = expectation(description: "thumbnail generation completes")
            Task {
                let image = await ThumbnailLoader.cgImage(
                    for: sourceURL,
                    kind: .image,
                    maxPixelSize: 512
                )
                result.set(image)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 10)
        }

        XCTAssertNotNil(result.image, "A thumbnail should be produced from the generated image fixture")
    }

    private func makeDeterministicPNG(at url: URL, width: Int, height: Int) throws {
        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            throw CocoaError(.fileWriteUnknown)
        }

        context.setFillColor(red: 0.18, green: 0.42, blue: 0.76, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 0.86, green: 0.28, blue: 0.14, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        context.setFillColor(red: 0.24, green: 0.70, blue: 0.38, alpha: 1)
        context.fill(CGRect(x: width / 2, y: height / 2, width: width / 2, height: height / 2))

        guard let image = context.makeImage() else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

private final class LockedThumbnailResult: @unchecked Sendable {
    private let lock = NSLock()
    private var value: CGImage?

    var image: CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ image: CGImage?) {
        lock.lock()
        value = image
        lock.unlock()
    }
}
