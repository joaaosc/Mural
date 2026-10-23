import Foundation
import Testing

@testable import MuralKit

private enum BoardLibraryConcurrentResult: Sendable {
    case bootstrap(LibraryState)
    case list([BoardLibraryEntry])
}

@Suite("Biblioteca de murais")
struct BoardLibraryTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MuralLibrary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Descoberta usa somente manifests e ordem determinística")
    func discoveryUsesManifests() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let first = try await library.createNamedBoard("Zeta")
        let second = try await library.createNamedBoard("Alpha")
        let boards = await library.boardsDirectory
        try Data("catálogo antigo".utf8).write(to: boards.appendingPathComponent("catalog.json"))
        try FileManager.default.createDirectory(at: boards.appendingPathComponent("sem-manifest.mural"), withIntermediateDirectories: true)
        let entries = try await library.listSaved()
        #expect(entries.map(\.route) == [second, first])
    }

    @Test("Criar B vazio não altera A")
    func createDoesNotAlterExistingBoard() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let routeA = try await library.createNamedBoard("A")
        let before = try #require(await library.open(routeA))
        let routeB = try await library.createNamedBoard("B")
        let after = try #require(await library.open(routeA))
        #expect(routeA != routeB)
        #expect(after.board == before.board)
        #expect(after.workspace == before.workspace)
    }

    @Test("Renomear não altera Board nem workspace")
    func renamePreservesSnapshotData() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Antes")
        let before = try #require(await library.open(route))
        _ = try await library.rename(route, to: "Depois")
        let after = try #require(await library.open(route))
        #expect(after.board == before.board)
        #expect(after.workspace == before.workspace)
        #expect(after.manifest.name == "Depois")
    }

    @Test("Welcome mantém UUID estável entre launches")
    func welcomeIDIsStable() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = BoardLibrary(rootDirectory: directory)
        let firstState = try await first.bootstrap()
        let second = BoardLibrary(rootDirectory: directory)
        let secondState = try await second.bootstrap()
        #expect(firstState.lifecycle == .draft)
        #expect(secondState.stableWelcomeID == firstState.stableWelcomeID)
        #expect(try await second.open(.welcomeDraft(secondState.stableWelcomeID)) != nil)
    }

    @Test("Bootstrap e list concorrentes publicam Welcome uma única vez")
    func concurrentBootstrapAndListAreSingleFlight() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)

        let results = try await withThrowingTaskGroup(of: BoardLibraryConcurrentResult.self) { group in
            for index in 0..<32 {
                if index.isMultiple(of: 2) {
                    group.addTask { .bootstrap(try await library.bootstrap()) }
                } else {
                    group.addTask { .list(try await library.list()) }
                }
            }

            var results: [BoardLibraryConcurrentResult] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }

        let states = results.compactMap { result -> LibraryState? in
            guard case .bootstrap(let state) = result else { return nil }
            return state
        }
        let firstState = try #require(states.first)
        #expect(states.count == 16)
        #expect(states.allSatisfy { $0.lifecycle == .draft })
        #expect(states.allSatisfy { $0.stableWelcomeID == firstState.stableWelcomeID })

        let lists = results.compactMap { result -> [BoardLibraryEntry]? in
            guard case .list(let entries) = result else { return nil }
            return entries
        }
        #expect(lists.count == 16)
        #expect(
            lists.allSatisfy { entries in
                entries.count == 1
                    && entries.first?.route == .welcomeDraft(firstState.stableWelcomeID)
            })

        let state = try #require(await library.lifecycleState())
        #expect(state.lifecycle == .draft)
        #expect(state.stableWelcomeID == firstState.stableWelcomeID)

        let package = (await library.draftsDirectory).appendingPathComponent("Welcome.mural", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: package.appendingPathComponent("manifest.json").path))
        #expect(FileManager.default.fileExists(atPath: package.appendingPathComponent("board.json").path))
        #expect(FileManager.default.fileExists(atPath: package.appendingPathComponent("view-state.json").path))
        #expect(FileManager.default.fileExists(atPath: package.appendingPathComponent("Items", isDirectory: true).path))

        let draftPackages = try FileManager.default.contentsOfDirectory(
            at: await library.draftsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "mural" }
        #expect(draftPackages.map(\.standardizedFileURL) == [package.standardizedFileURL])
    }

    @Test("Migração copia board e assets e preserva legado")
    func legacyMigrationCopiesWithoutDeletingSource() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyBoard = Board(items: [BoardItem(kind: .text, title: "Legado")])
        let legacyStore = BoardStore(directory: directory)
        try legacyStore.save(legacyBoard)
        try FileManager.default.createDirectory(at: legacyStore.itemsDirectory, withIntermediateDirectories: true)
        let asset = legacyStore.itemsDirectory.appendingPathComponent("asset.bin")
        try Data([1, 2, 3]).write(to: asset)
        let library = BoardLibrary(rootDirectory: directory)
        let state = try await library.bootstrap()
        let draft = try #require(await library.open(.welcomeDraft(state.stableWelcomeID)))
        let persistedLegacy = try #require(try legacyStore.load())
        #expect(draft.board == persistedLegacy)
        #expect(FileManager.default.fileExists(atPath: legacyStore.fileURL.path))
        #expect(FileManager.default.fileExists(atPath: asset.path))
        #expect(
            FileManager.default.fileExists(
                atPath: (await library.draftsDirectory).appendingPathComponent("Welcome.mural/Items/asset.bin").path))
    }

    @Test("Falha de migração depois da publicação é recuperável e idempotente")
    func migrationFailureRecoversDraft() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let failing = BoardLibrary(
            rootDirectory: directory,
            faultInjection: BoardLibraryFaultInjection(points: [.afterDraftPublish])
        )
        await #expect(throws: BoardLibraryError.self) { _ = try await failing.bootstrap() }
        let recovered = BoardLibrary(rootDirectory: directory)
        let state = try await recovered.bootstrap()
        #expect(state.lifecycle == .draft)
        let next = try await recovered.bootstrap()
        #expect(next.stableWelcomeID == state.stableWelcomeID)
    }

    @Test("Promoção falha sem perder o draft e depois não faz reseed")
    func promotionFailureKeepsDraft() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let initial = BoardLibrary(rootDirectory: directory)
        let state = try await initial.bootstrap()
        let failing = BoardLibrary(
            rootDirectory: directory,
            faultInjection: BoardLibraryFaultInjection(points: [.beforePromotionPublish])
        )
        await #expect(throws: BoardLibraryError.self) {
            _ = try await failing.promoteWelcomeDraft(name: "Promovido")
        }
        let draftAfterFailure = try #require(await failing.open(.welcomeDraft(state.stableWelcomeID)))
        #expect(draftAfterFailure.board == (try #require(await initial.open(.welcomeDraft(state.stableWelcomeID))).board))
        let promoted = try await BoardLibrary(rootDirectory: directory).promoteWelcomeDraft(name: "Promovido")
        let promotedSnapshot = try #require(await BoardLibrary(rootDirectory: directory).open(promoted))
        #expect(promotedSnapshot.manifest.name == "Promovido")
        let finalState = try #require(try await BoardLibrary(rootDirectory: directory).lifecycleState())
        #expect(finalState.lifecycle == .promoted)
        #expect(finalState.promotedBoardID != nil)
    }

    @Test("Falha depois da publicação da promoção recupera sem duplicar")
    func promotionAfterPublishFailureRecovers() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let initial = BoardLibrary(rootDirectory: directory)
        let state = try await initial.bootstrap()
        let failing = BoardLibrary(
            rootDirectory: directory,
            faultInjection: BoardLibraryFaultInjection(points: [.afterPromotionPublish])
        )
        await #expect(throws: BoardLibraryError.self) {
            _ = try await failing.promoteWelcomeDraft(name: "Promovido")
        }
        let recovered = BoardLibrary(rootDirectory: directory)
        let route = try await recovered.promoteWelcomeDraft(name: "Promovido")
        let finalState = try #require(try await recovered.lifecycleState())
        #expect(finalState.lifecycle == .promoted)
        #expect(finalState.promotedBoardID != nil)
        #expect(try await recovered.open(route) != nil)
        await #expect(throws: BoardLibraryError.self) {
            _ = try await recovered.open(.welcomeDraft(state.stableWelcomeID))
        }
    }

    @Test("Discard marca lifecycle antes da limpeza e não faz reseed")
    func discardDoesNotReseed() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let state = try await library.bootstrap()
        try await library.discardWelcomeDraft()
        let next = try await BoardLibrary(rootDirectory: directory).bootstrap()
        #expect(next.lifecycle == .discarded)
        #expect(next.stableWelcomeID == state.stableWelcomeID)
        await #expect(throws: BoardLibraryError.self) {
            _ = try await library.open(.welcomeDraft(state.stableWelcomeID))
        }
    }

    @Test("Falha de limpeza do descarte não reverte o lifecycle")
    func discardFailureDoesNotReseed() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let initial = BoardLibrary(rootDirectory: directory)
        let state = try await initial.bootstrap()
        let failing = BoardLibrary(
            rootDirectory: directory,
            faultInjection: BoardLibraryFaultInjection(points: [.beforeDiscardCleanup])
        )
        await #expect(throws: BoardLibraryError.self) { try await failing.discardWelcomeDraft() }
        let recovered = BoardLibrary(rootDirectory: directory)
        let finalState = try #require(try await recovered.lifecycleState())
        #expect(finalState.lifecycle == .discarded)
        #expect(finalState.stableWelcomeID == state.stableWelcomeID)
        await #expect(throws: BoardLibraryError.self) {
            _ = try await recovered.open(.welcomeDraft(state.stableWelcomeID))
        }
    }

    @Test("Registry reutiliza sessão e recarrega depois de fechar")
    func registrySharesAndReloadsSessions() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Mural")
        let registry = BoardSessionRegistry(library: library)
        let first = try await registry.open(route)
        let second = try await registry.open(route)
        #expect(first === second)
        let id: BoardID = if case .saved(let value) = route { value } else { BoardID() }
        await registry.close(id)
        let third = try await registry.open(route)
        #expect(third !== first)
    }

    @Test("Rota indisponível não cria mural vazio")
    func unavailableRouteDoesNotCreateBoard() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let id = BoardID()
        await #expect(throws: BoardLibraryError.self) {
            _ = try await library.open(.saved(id))
        }
        #expect(try await library.listSaved().isEmpty)
    }
}
