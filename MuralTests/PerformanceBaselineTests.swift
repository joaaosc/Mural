import Foundation
import MuralKit
import XCTest

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
}
