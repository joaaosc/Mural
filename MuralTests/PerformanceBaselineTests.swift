import CoreGraphics
import Foundation
import MuralKit
import XCTest

@testable import Mural

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

    func testCanvasCullingWithDisplayedSizesPerformance() {
        let items = (0..<2_000).map { index in
            let kind: ItemKind = index.isMultiple(of: 3) ? .sticky : .image
            let position = BoardPoint(
                x: Double((index % 100) * 180),
                y: Double((index / 100) * 220))
            let size: BoardSize? = index.isMultiple(of: 3) ? BoardSize(width: 160, height: 160) : nil
            return BoardItem(
                kind: kind,
                title: "Culling item \(index)",
                position: position,
                size: size)
        }
        let freeTexts = (0..<2_000).map { index in
            let position = BoardPoint(
                x: Double((index % 100) * 180),
                y: Double((index / 100) * 220 + 40))
            let size: BoardSize? = index.isMultiple(of: 4) ? BoardSize(width: 260, height: 120) : nil
            return BoardFreeText(
                text: "Culling text \(index)",
                position: position,
                size: size)
        }
        let itemSizes: [UUID: BoardSize] = Dictionary(
            uniqueKeysWithValues: items.map { item in
                let size = BoardLayout.size(of: item)
                return (item.id, BoardSize(width: size.width, height: size.height))
            })
        let freeTextSizes: [UUID: BoardSize] = Dictionary(
            uniqueKeysWithValues: freeTexts.map { freeText in
                let size = BoardLayout.size(of: freeText)
                return (freeText.id, BoardSize(width: size.width, height: size.height))
            })
        let viewport = CGRect(x: 1_800, y: 1_800, width: 1_200, height: 900)
        var visibleCount = 0

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let visibleItems = CanvasRenderCulling.visibleItems(
                items,
                in: viewport,
                overscan: 1,
                displayedSizes: itemSizes)
            let visibleFreeTexts = CanvasRenderCulling.visibleFreeTexts(
                freeTexts,
                in: viewport,
                overscan: 1,
                displayedSizes: freeTextSizes)
            visibleCount = visibleItems.count + visibleFreeTexts.count
        }

        XCTAssertGreaterThan(visibleCount, 0)
        XCTAssertLessThan(visibleCount, items.count + freeTexts.count)
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
        _ = model.reminderItems
        _ = model.rootExtent
        for id in folderIDs {
            _ = model.children(of: id)
        }

        var derivedCount = 0
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            derivedCount += model.rootItems.count
            derivedCount += model.freeTexts.count
            derivedCount += model.reminderItems.count
            derivedCount += Int(model.rootExtent.width)
            for id in folderIDs {
                derivedCount += model.children(of: id).count
            }
        }

        XCTAssertGreaterThan(derivedCount, 0)
    }

    func testCachedCanvasSizeSnapshotsPerformance() throws {
        let board = PerformanceBoardFixture.make(size: .items500, mediaDensity: .percent50)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerformanceBoardSizeSnapshots-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = BoardModel(
            board: board,
            store: BoardStore(directory: directory),
            persistence: .deferred)
        _ = model.rootItemSizes
        _ = model.freeTextSizes

        var sizeCount = 0
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            sizeCount = model.rootItemSizes.count + model.freeTextSizes.count
        }

        XCTAssertEqual(sizeCount, board.rootItems.count + board.freeTexts.count)
    }

    func testIndexedItemLookupPerformance() throws {
        let board = PerformanceBoardFixture.make(size: .items500, mediaDensity: .percent50)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerformanceBoardItemLookup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = BoardModel(
            board: board,
            store: BoardStore(directory: directory),
            persistence: .deferred)
        let ids = Array(board.items.prefix(200).map(\.id))
        for id in ids {
            _ = model.item(id: id)
        }

        var foundCount = 0
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            foundCount = ids.reduce(into: 0) { count, id in
                if model.item(id: id) != nil { count += 1 }
            }
        }

        XCTAssertEqual(foundCount, ids.count)
    }

    func testIndexedFreeTextLookupPerformance() throws {
        let freeTexts = (0..<200).map { index in
            BoardFreeText(
                id: UUID(),
                text: "Fixture free text \(index)",
                position: BoardPoint(x: Double(index * 20), y: Double(index * 8)))
        }
        let board = Board(freeTexts: freeTexts)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerformanceBoardFreeTextLookup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let model = BoardModel(
            board: board,
            store: BoardStore(directory: directory),
            persistence: .deferred)
        let ids = freeTexts.map(\.id)
        for id in ids {
            _ = model.freeText(id: id)
        }

        var foundCount = 0
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            foundCount = ids.reduce(into: 0) { count, id in
                if model.freeText(id: id) != nil { count += 1 }
            }
        }

        XCTAssertEqual(foundCount, ids.count)
    }

    func testBoardModelBatchImportPerformance() throws {
        let board = PerformanceBoardFixture.make(size: .items500, mediaDensity: .percent50)
        let snapshots = (0..<200).map { index in
            MusicSnapshot(
                kind: .song,
                catalogID: "fixture-song-\(index)",
                title: "Fixture song \(index)")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerformanceBoardBatchImport-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var createdCount = 0
        let options = XCTMeasureOptions()

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            let model = BoardModel(
                board: board,
                store: BoardStore(directory: directory),
                persistence: .deferred)
            createdCount = model.importMusic(snapshots).count
        }

        XCTAssertEqual(createdCount, snapshots.count)
    }

    func testBatchImportPositioningPerformance() throws {
        let board = PerformanceBoardFixture.make(size: .items500, mediaDensity: .percent50)
        let kinds = Array(repeating: ItemKind.image, count: 200)
        var positions: [BoardPoint] = []

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            positions = BoardLayout.importPositions(kinds: kinds, anchor: nil, avoiding: board.rootItems)
        }

        XCTAssertEqual(positions.count, kinds.count)
        var occupied = board.rootItems
        let reference = kinds.map { kind in
            let position = BoardLayout.freePosition(for: kind, avoiding: occupied)
            occupied.append(BoardItem(kind: kind, title: "", position: position))
            return position
        }
        XCTAssertEqual(positions, reference)
    }

    func testSequentialImportPositioningReferencePerformance() throws {
        let board = PerformanceBoardFixture.make(size: .items500, mediaDensity: .percent50)
        let kinds = Array(repeating: ItemKind.image, count: 200)
        var positions: [BoardPoint] = []

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            var occupied = board.rootItems
            positions = kinds.map { kind in
                let position = BoardLayout.freePosition(for: kind, avoiding: occupied)
                occupied.append(BoardItem(kind: kind, title: "", position: position))
                return position
            }
        }

        XCTAssertEqual(positions.count, kinds.count)
    }

    func testBoardScanPerItemImportPositioningReferencePerformance() throws {
        let board = PerformanceBoardFixture.make(size: .items500, mediaDensity: .percent50)
        let kinds = Array(repeating: ItemKind.image, count: 200)
        var insertedCount = 0

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            var workingBoard = board
            for kind in kinds {
                let position = BoardLayout.freePosition(for: kind, avoiding: workingBoard.rootItems)
                workingBoard.add(BoardItem(kind: kind, title: "", position: position))
            }
            insertedCount = workingBoard.items.count - board.items.count
        }

        XCTAssertEqual(insertedCount, kinds.count)
    }
}
