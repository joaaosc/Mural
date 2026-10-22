import Foundation
import Testing

@testable import MuralKit

/// Gravação no lugar, mídia intocada, rollback, publicação sem perda e exportação
/// só do que o board referencia.
@Suite("Gravação segura no repositório")
struct RepositorySafetyTests {
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

    @Test("Mídia gravada durante dezenas de autosaves nunca se perde")
    func concurrentImportDuringSavesKeepsMedia() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = BoardRepository(rootDirectory: root)
        let id = BoardID()
        try await repository.save(id: id, board: Board(), workspace: .default, manifest: manifest(id))
        let items = await repository.packageURL(for: id).appendingPathComponent("Items", isDirectory: true)
        let importer = ItemImporter(itemsDirectory: items)

        // O importador grava direto em `Items/` (como o BoardModel faz no app) enquanto
        // o repositório publica revisões novas sem parar.
        let writer = Task.detached { () -> [String] in
            var names: [String] = []
            for index in 0..<60 {
                let item = try importer.importData(
                    Data(repeating: UInt8(index % 251), count: 2048), fileExtension: "png", kind: .image,
                    title: "img \(index)")
                names.append(try #require(item.fileName))
                await Task.yield()
            }
            return names
        }
        for revision in 2...61 {
            let board = Board(items: [BoardItem(kind: .text, title: "rev \(revision)")])
            try await repository.save(id: id, board: board, workspace: .default, manifest: manifest(id, content: revision))
        }
        let written = try await writer.value
        for name in written {
            #expect(FileManager.default.fileExists(atPath: items.appendingPathComponent(name).path), "perdeu \(name)")
        }
        #expect(transactionArtifacts(in: root).isEmpty)
    }

    @Test("Gravações só de workspace não tocam a mídia nem criam staging")
    func workspaceSavesLeaveItemsUntouched() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = BoardRepository(rootDirectory: root)
        let id = BoardID()
        let board = Board(items: [BoardItem(kind: .image, title: "Foto", fileName: "foto.png")])
        try await repository.save(id: id, board: board, workspace: .default, manifest: manifest(id))
        let package = await repository.packageURL(for: id)
        let photo = package.appendingPathComponent("Items/foto.png")
        try Data([1, 2, 3]).write(to: photo)
        let packageInode = try inode(of: package)
        let photoInode = try inode(of: photo)
        let boardInode = try inode(of: package.appendingPathComponent("board.json"))

        for revision in 1...20 {
            let workspace = BoardWorkspaceState(
                contentRevision: 1, canvas: CanvasWorkspaceState(confirmedZoom: 1 + Double(revision) / 100))
            try await repository.save(
                id: id, board: board, workspace: workspace, manifest: manifest(id, content: 1, workspace: revision))
        }

        #expect(try inode(of: package) == packageInode, "o diretório do package foi trocado")
        #expect(try inode(of: photo) == photoInode, "a mídia foi copiada")
        #expect(try inode(of: package.appendingPathComponent("board.json")) == boardInode, "board.json regravado sem mudança de conteúdo")
        #expect(try await repository.load(id)?.snapshot.workspace.canvas.confirmedZoom == 1.2)
        #expect(transactionArtifacts(in: root).isEmpty)
    }

    @Test("Falha antes do commit no lugar devolve board e workspace anteriores")
    func inPlaceRollbackRestoresBoardAndWorkspace() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = BoardID()
        let baselineBoard = Board(items: [BoardItem(kind: .sticky, title: "antes")])
        let baselineWorkspace = BoardWorkspaceState(contentRevision: 1, canvas: CanvasWorkspaceState(confirmedZoom: 1.5))
        try await BoardRepository(rootDirectory: root).save(
            id: id, board: baselineBoard, workspace: baselineWorkspace, manifest: manifest(id, content: 1, workspace: 1))
        let failing = BoardRepository(
            rootDirectory: root, faultInjection: BoardRepositoryFaultInjection(points: [.afterSwap]))
        await #expect(throws: BoardRepositoryError.injectedFailure(.afterSwap)) {
            try await failing.save(
                id: id, board: Board(items: [BoardItem(kind: .sticky, title: "depois")]),
                workspace: BoardWorkspaceState(contentRevision: 2, canvas: CanvasWorkspaceState(confirmedZoom: 2)),
                manifest: manifest(id, content: 2, workspace: 2))
        }
        let loaded = try #require(try await BoardRepository(rootDirectory: root).load(id))
        #expect(loaded.snapshot.board == baselineBoard)
        #expect(loaded.snapshot.workspace.canvas.confirmedZoom == 1.5)
        #expect(loaded.snapshot.manifest.contentRevision == 1)
        #expect(transactionArtifacts(in: root).isEmpty)
    }

    @Test("Publicação nova nunca apaga o package anterior quando algo recria o caminho")
    func publishWithIntruderKeepsPreviousPackage() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = BoardID()
        let baseline = Board(items: [BoardItem(kind: .sticky, title: "original")])
        try await BoardRepository(rootDirectory: root).save(
            id: id, board: baseline, workspace: .default, manifest: manifest(id))
        let source = root.appendingPathComponent("source-items", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        let failing = BoardRepository(
            rootDirectory: root, faultInjection: BoardRepositoryFaultInjection(points: [.intruderBeforeMove]))
        await #expect(throws: BoardRepositoryError.self) {
            try await failing.save(
                BoardRepositorySnapshot(
                    manifest: manifest(id, content: 2), board: Board(items: [BoardItem(kind: .sticky, title: "novo")])),
                copyingItemsFrom: source)
        }
        #expect(try await BoardRepository(rootDirectory: root).load(id)?.snapshot.board == baseline)
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(names.contains { $0.contains(".mural-intruder-") }, "o intruso deveria ser guardado à parte")
        #expect(!names.contains { $0.contains(".mural-backup-") || $0.contains(".mural-staging-") })
    }

    @Test("Exportação leva só a mídia referenciada e acusa a que falta")
    func exportCopiesOnlyReferencedMedia() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = BoardLibrary(rootDirectory: root)
        let route = try await library.createNamedBoard("Exportar")
        let id = try #require(route.id)
        let repository = try await library.repository(for: route)
        let board = Board(items: [BoardItem(kind: .image, title: "Foto", fileName: "foto.png")])
        try await repository.save(BoardRepositorySnapshot(manifest: manifest(id, name: "Exportar"), board: board))
        let items = await repository.packageURL(for: id).appendingPathComponent("Items", isDirectory: true)
        try Data([1, 2, 3, 4]).write(to: items.appendingPathComponent("foto.png"))
        try Data([9, 9]).write(to: items.appendingPathComponent("orfao.png"))

        let exported = try await library.exportPackage(route)
        let exportedItems = try FileManager.default.contentsOfDirectory(
            atPath: exported.appendingPathComponent("Items").path)
        #expect(exportedItems == ["foto.png"])
        try await library.cleanupTransfer(exported)

        try FileManager.default.removeItem(at: items.appendingPathComponent("foto.png"))
        await #expect(throws: BoardRepositoryError.missingAsset("foto.png")) {
            _ = try await library.exportPackage(route)
        }
    }

    @Test("Custo de autosave só de workspace com centenas de mídias")
    func workspaceAutosaveCostWithManyMediaFiles() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = BoardRepository(rootDirectory: root)
        let id = BoardID()
        var items: [BoardItem] = []
        for index in 0..<300 {
            items.append(BoardItem(kind: .image, title: "img \(index)", fileName: "img-\(index).png"))
        }
        let board = Board(items: items)
        try await repository.save(id: id, board: board, workspace: .default, manifest: manifest(id))
        let media = await repository.packageURL(for: id).appendingPathComponent("Items", isDirectory: true)
        for index in 0..<300 {
            try Data(repeating: 7, count: 64 * 1024).write(to: media.appendingPathComponent("img-\(index).png"))
        }
        let clock = ContinuousClock()
        let elapsed = try await clock.measure {
            for revision in 1...50 {
                let workspace = BoardWorkspaceState(
                    contentRevision: 1, canvas: CanvasWorkspaceState(confirmedZoom: 1 + Double(revision) / 1000))
                try await repository.save(
                    id: id, board: board, workspace: workspace, manifest: manifest(id, content: 1, workspace: revision))
            }
        }
        print("50 autosaves de workspace com 300 mídias: \(elapsed)")
        // Folga enorme: só pega regressão grosseira (voltar a copiar `Items/` inteira).
        #expect(elapsed < .seconds(20))
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
