import Foundation
import Testing

@testable import MuralKit

/// Sessão única por mural, donos, aposentadoria, renomeação e lista tolerante.
@Suite("Sessões, registry e biblioteca")
struct SessionRegistryTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralPersistence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func manifest(_ id: BoardID, content: Int = 1, workspace: Int = 0, name: String = "Mural") -> BoardManifest {
        BoardManifest(id: id, name: name, contentRevision: content, workspaceRevision: workspace)
    }

    private func inode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.systemFileNumber] as? Int)
    }

    /// Nomes de artefatos de transação em qualquer nível abaixo de `root`.
    private func transactionArtifacts(in root: URL) -> [String] {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        var found: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            let name = url.lastPathComponent
            if name.contains(".mural-staging-") || name.contains(".mural-backup-") || name.contains(".backup-") {
                found.append(name)
            }
        }
        return found
    }

    @Test("Um package danificado não esconde os outros murais")
    func listingSkipsUnreadablePackages() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = BoardLibrary(rootDirectory: root)
        let good = try await library.createNamedBoard("Bom")
        let corrupted = try #require(try await library.createNamedBoard("Corrompido").id)
        let future = try #require(try await library.createNamedBoard("Futuro").id)
        let boards = root.appendingPathComponent("Boards", isDirectory: true)
        try Data("{".utf8).write(
            to: boards.appendingPathComponent("\(corrupted.rawValue.uuidString).mural/manifest.json"))
        let futureManifest = boards.appendingPathComponent("\(future.rawValue.uuidString).mural/manifest.json")
        let text = try String(contentsOf: futureManifest, encoding: .utf8)
            .replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 99")
        try text.write(to: futureManifest, atomically: true, encoding: .utf8)

        let report = try await library.listSavedReport()
        #expect(report.entries.map(\.route) == [good])
        #expect(report.unreadable.count == 2)
        #expect(try await library.list().contains { $0.route == good })
    }

    @Test("Abrir o mesmo mural ao mesmo tempo devolve uma única sessão")
    func concurrentOpenIsSingleFlight() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = BoardLibrary(rootDirectory: root)
        let route = try await library.createNamedBoard("Único")
        let registry = BoardSessionRegistry(library: library)
        let sessions = try await withThrowingTaskGroup(of: BoardSession.self) { group in
            for index in 0..<32 {
                group.addTask {
                    index.isMultiple(of: 2) ? try await registry.open(route) : try await registry.acquire(route)
                }
            }
            var result: [BoardSession] = []
            for try await session in group { result.append(session) }
            return result
        }
        let first = try #require(sessions.first)
        #expect(sessions.allSatisfy { $0 === first })
        #expect(await registry.ownerCount(for: try #require(route.id)) == 16)
    }

    @Test("A sessão só é aposentada quando o último dono solta e ela está limpa")
    func registryOwnershipAndRetirement() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = BoardLibrary(rootDirectory: root)
        let route = try await library.createNamedBoard("Donos")
        let id = try #require(route.id)
        let registry = BoardSessionRegistry(library: library)

        let first = try await registry.acquire(route)
        let second = try await registry.acquire(route)
        #expect(first === second)
        #expect(await registry.release(id) == false)
        #expect(await registry.session(for: id) === first)
        #expect(await first.isRetired == false)

        // Suja e sem donos: continua registrada para a próxima janela recuperar.
        try await first.update(board: Board(items: [BoardItem(kind: .sticky, title: "pendente")]))
        #expect(await registry.release(id) == false)
        let recovered = try await registry.acquire(route)
        #expect(recovered === first)
        _ = try await recovered.flush()
        #expect(await registry.release(id))
        #expect(await registry.session(for: id) == nil)
        #expect(await first.isRetired)

        // Aposentada: nada mais chega ao disco.
        let saved = try #require(try await library.open(route))
        await #expect(throws: BoardSessionError.retired) {
            try await first.update(board: Board(items: [BoardItem(kind: .sticky, title: "tardio")]))
        }
        await #expect(throws: BoardSessionError.retired) { _ = try await first.flush() }
        #expect(try await library.open(route) == saved)
        let reopened = try await registry.acquire(route)
        #expect(reopened !== first)
    }

    @Test("Renomear pela sessão grava o nome sem mexer no conteúdo")
    func renameThroughSession() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = BoardLibrary(rootDirectory: root)
        let route = try await library.createNamedBoard("Antigo")
        let registry = BoardSessionRegistry(library: library)
        let session = try await registry.acquire(route)
        let before = try #require(try await library.open(route))

        try await session.rename(to: "Novo")
        _ = try await session.flush()
        let after = try #require(try await library.open(route))
        #expect(after.manifest.name == "Novo")
        #expect(after.board == before.board)
        #expect(after.workspace == before.workspace)

        await session.retire()
        await #expect(throws: BoardSessionError.retired) { try await session.rename(to: "Velho de novo") }
        #expect(try await library.open(route)?.manifest.name == "Novo")
    }
}

extension BoardRoute {
    fileprivate var id: BoardID? {
        switch self {
        case .library: nil
        case .welcomeDraft(let id), .saved(let id): id
        }
    }
}
