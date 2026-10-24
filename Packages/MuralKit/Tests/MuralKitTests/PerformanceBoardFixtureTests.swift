import Foundation
import Testing

@testable import MuralKit

@Suite("Fixtures estruturais de performance")
struct PerformanceBoardFixtureTests {
    @Test("A mesma configuração gera o mesmo mural")
    func isReproducible() {
        let first = PerformanceBoardFixture.make(size: .items500, mediaDensity: .percent50)
        let second = PerformanceBoardFixture.make(size: .items500, mediaDensity: .percent50)

        #expect(first == second)
        #expect(first.items.map(\.id) == second.items.map(\.id))
        #expect(first.items.map(\.createdAt) == second.items.map(\.createdAt))
        #expect(first.items.map(\.position) == second.items.map(\.position))
    }

    @Test("Os perfis têm a contagem e a densidade exatas")
    func hasExpectedCountAndMediaDensity() {
        for size in PerformanceFixtureSize.allCases {
            for density in PerformanceFixtureMediaDensity.allCases {
                let board = PerformanceBoardFixture.make(size: size, mediaDensity: density)
                let mediaCount = board.items.filter { $0.kind.storesFile }.count

                #expect(board.items.count == size.rawValue)
                #expect(mediaCount == size.rawValue * density.rawValue / 100)
            }
        }
    }

    @Test("A fixture contém todos os tipos e os dois estados de prévia")
    func containsRepresentativeKindsAndPreviews() {
        let board = PerformanceBoardFixture.make(size: .items100, mediaDensity: .percent10)
        let kinds = Set(board.items.map(\.kind.rawValue))

        for kind in ItemKind.allCases {
            #expect(kinds.contains(kind.rawValue), "faltou o tipo \(kind.rawValue)")
        }

        let links = board.items.compactMap(\.link)
        let expectedPreviewDate = Date(timeIntervalSince1970: 1_735_689_606.5)
        #expect(
            links.contains {
                $0.previewImageFile != nil && $0.preview == .ready(fetchedAt: expectedPreviewDate)
            }
        )
        #expect(links.contains { $0.previewImageFile == nil && $0.preview == .pending })

        let media = board.items.filter { $0.kind.storesFile }
        #expect(media.allSatisfy { $0.fileName?.hasPrefix("structural-fixture-") == true })
    }

    @Test("As posições dos cartões são determinísticas e distribuídas")
    func distributesPositions() {
        let board = PerformanceBoardFixture.make(size: .items2000, mediaDensity: .percent50)
        let root = board.rootItems
        let positions = Set(root.map(\.position))
        let xs = root.map(\.position.x)
        let ys = root.map(\.position.y)

        #expect(root.count > 100)
        #expect(positions.count == root.count)
        #expect((xs.max() ?? 0) > (xs.min() ?? 0))
        #expect((ys.max() ?? 0) > (ys.min() ?? 0))
    }

    @Test("A hierarquia não tem ciclos e respeita o limite de profundidade")
    func hierarchyIsValid() {
        let board = PerformanceBoardFixture.make(size: .items2000, mediaDensity: .percent90)
        let byID = Dictionary(uniqueKeysWithValues: board.items.map { ($0.id, $0) })

        for item in board.items {
            if let parentID = item.parentID {
                #expect(byID[parentID]?.kind == .folder, "pai inválido para \(item.title)")
            }

            var visited: Set<UUID> = [item.id]
            var current = item.parentID
            var depth = 0
            while let parentID = current {
                guard visited.insert(parentID).inserted, let parent = byID[parentID] else {
                    #expect(Bool(false), "ciclo ou pai ausente em \(item.title)")
                    break
                }
                #expect(parent.kind == .folder)
                depth += 1
                #expect(depth <= Board.maximumFolderDepth)
                current = parent.parentID
            }
        }

        let folders = board.items.filter { $0.kind == .folder }
        #expect(folders.contains { board.depth(of: $0.id) == 0 })
        #expect(folders.contains { board.depth(of: $0.id) >= 2 })
    }
}
