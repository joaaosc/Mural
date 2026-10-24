import Foundation
import MuralKit
import XCTest

@MainActor
final class PerformanceBaselineTests: XCTestCase {
    func testStructuralBoardReadAndEncodingPerformance() throws {
        let board = PerformanceBoardFixture.make(size: .items500, mediaDensity: .percent50)
        let rootFolder = try XCTUnwrap(board.rootItems.first { $0.kind == .folder })
        let destinationSource = try XCTUnwrap(board.items.last)
        let encoder = JSONEncoder()

        var rootCount = 0
        var childCount = 0
        var descendantCount = 0
        var destinationCount = 0
        var encodedByteCount = 0

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            rootCount = board.rootItems.count
            childCount = board.children(of: rootFolder.id).count
            descendantCount = board.descendants(of: rootFolder.id).count
            destinationCount = board.folderDestinations(for: destinationSource.id).count

            do {
                encodedByteCount = try encoder.encode(board).count
            } catch {
                XCTFail("A codificação JSON da fixture falhou: \(error)")
            }
        }

        XCTAssertGreaterThan(rootCount, 0)
        XCTAssertGreaterThan(childCount, 0)
        XCTAssertGreaterThanOrEqual(descendantCount, childCount)
        XCTAssertGreaterThan(destinationCount, 0)
        XCTAssertGreaterThan(encodedByteCount, 0)
    }

    func testCachedFolderDestinationLookupPerformance() throws {
        let board = PerformanceBoardFixture.make(size: .items500, mediaDensity: .percent50)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerformanceBoardModel-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = BoardModel(
            board: board,
            store: BoardStore(directory: directory),
            persistence: .deferred)
        let ids = Array(board.items.prefix(200).map(\.id))
        for id in ids {
            _ = model.folderDestinations(for: id)
        }

        var destinationCount = 0
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            destinationCount = ids.reduce(into: 0) { total, id in
                total += model.folderDestinations(for: id).count
            }
        }

        XCTAssertGreaterThan(destinationCount, 0)
    }

    func testCachedBoardDerivedReadsPerformance() throws {
        let board = PerformanceBoardFixture.make(size: .items500, mediaDensity: .percent50)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerformanceBoardDerivedReads-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = BoardModel(
            board: board,
            store: BoardStore(directory: directory),
            persistence: .deferred)
        let folderIDs = board.items.filter { $0.kind == .folder }.map(\.id)
        _ = model.rootItems
        _ = model.freeTexts
        _ = model.rootExtent
        for id in folderIDs {
            _ = model.children(of: id)
        }

        var derivedCount = 0
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            derivedCount += model.rootItems.count
            derivedCount += model.freeTexts.count
            derivedCount += Int(model.rootExtent.width)
            for id in folderIDs {
                derivedCount += model.children(of: id).count
            }
        }

        XCTAssertGreaterThan(derivedCount, 0)
    }
}
