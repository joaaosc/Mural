import Foundation
import Testing

@testable import MuralKit

@Suite("Pacotes portáteis .mural")
struct BoardPortablePackageTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MuralPortable-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func package(at root: URL, board: Board, workspace: BoardWorkspaceState? = nil) throws -> URL {
        let package = root.appendingPathComponent("external-\(UUID().uuidString).mural", isDirectory: true)
        try FileManager.default.createDirectory(
            at: package.appendingPathComponent("Items", isDirectory: true), withIntermediateDirectories: true)
        let manifest = BoardManifest(id: BoardID(), name: "Transfer")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate)
        }
        try encoder.encode(manifest).write(to: package.appendingPathComponent("manifest.json"))
        try encoder.encode(board).write(to: package.appendingPathComponent("board.json"))
        if let workspace {
            try encoder.encode(workspace).write(to: package.appendingPathComponent("view-state.json"))
        }
        return package
    }

    @Test("Exportar e importar preserva dados e não altera a origem")
    func roundTripAndSourceIntegrity() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = BoardLibrary(rootDirectory: root)
        let route = try await library.createNamedBoard("Original")
        let id = try #require(route.id)
        let repository = try await library.repository(for: route)
        let folder = UUID()
        let assetID = UUID()
        let board = Board(items: [
            BoardItem(id: folder, kind: .folder, title: "Assets", position: BoardPoint(x: 1, y: 2)),
            BoardItem(id: assetID, kind: .image, title: "Image", parentID: folder, position: BoardPoint(x: 3, y: 4), fileName: "image.png"),
        ])
        let workspace = BoardWorkspaceState(contentRevision: 1, path: [.collection(folder)])
        try await repository.save(
            BoardRepositorySnapshot(
                manifest: BoardManifest(id: id, name: "Original", contentRevision: 1), board: board, workspace: workspace))
        let items = await repository.packageURL(for: id).appendingPathComponent("Items", isDirectory: true)
        try Data([1, 2, 3, 4]).write(to: items.appendingPathComponent("image.png"))
        let exported = try await library.exportPackage(route)
        let before = try snapshot(exported)
        let imported = try await library.importPackage(from: exported)
        let importedSnapshot = try #require(await library.open(imported))
        #expect(importedSnapshot.board == board)
        #expect(importedSnapshot.workspace == workspace)
        #expect(imported != route)
        #expect(try snapshot(exported) == before)
        #expect(FileManager.default.fileExists(atPath: exported.path))
        try await library.cleanupTransfer(exported)
        #expect(!FileManager.default.fileExists(atPath: exported.path))
    }

    @Test("Workspace ausente importa com defaults")
    func missingWorkspaceUsesDefaults() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try package(at: root, board: Board())
        let library = BoardLibrary(rootDirectory: root)
        let result = try await library.importPackageWithReport(from: package)
        #expect(result.workspaceStatus == .missing)
        #expect(try await library.open(result.route)?.workspace == .default)
    }

    @Test("Workspace corrompido não descarta o board e retorna aviso")
    func corruptWorkspaceUsesDefaults() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try package(at: root, board: Board(items: [BoardItem(kind: .text, title: "Board")]))
        try Data("not-json".utf8).write(to: package.appendingPathComponent("view-state.json"))
        let library = BoardLibrary(rootDirectory: root)
        let result = try await library.importPackageWithReport(from: package)
        guard case .corrupted = result.workspaceStatus else {
            Issue.record("workspace corrompido não retornou aviso")
            return
        }
        #expect(try await library.open(result.route)?.board.items.count == 1)
        #expect(try await library.listSaved().count == 1)
        let repository = try await library.repository(for: result.route)
        let savedPackage = await repository.packageURL(for: result.boardID)
        let diagnostics = try FileManager.default.contentsOfDirectory(at: savedPackage, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".view-state-corrupt-") }
        #expect(diagnostics.count == 1)
        #expect(try Data(contentsOf: try #require(diagnostics.first)) == Data("not-json".utf8))
        let legacyDiagnostic = savedPackage.appendingPathComponent("view-state-corrupt-legacy.json")
        try Data("legacy".utf8).write(to: legacyDiagnostic)
        var saved = try #require(await library.open(result.route))
        saved.manifest.contentRevision += 1
        try await repository.save(saved)
        let afterSave = try FileManager.default.contentsOfDirectory(at: savedPackage, includingPropertiesForKeys: nil)
        let importedAfterSave = afterSave.filter { $0.lastPathComponent.hasPrefix(".view-state-corrupt-") }
        #expect(importedAfterSave.count == 1)
        #expect(try Data(contentsOf: try #require(importedAfterSave.first)) == Data("not-json".utf8))
        #expect(try Data(contentsOf: savedPackage.appendingPathComponent(legacyDiagnostic.lastPathComponent)) == Data("legacy".utf8))
    }

    @Test("Schema futuro do manifest é rejeitado")
    func futureManifestSchemaIsRejected() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let future = try package(at: root, board: Board())
        var object = try jsonObject(at: future.appendingPathComponent("manifest.json"))
        object["schemaVersion"] = BoardManifest.currentSchemaVersion + 1
        try JSONSerialization.data(withJSONObject: object).write(to: future.appendingPathComponent("manifest.json"))
        let service = BoardPortablePackageService(availableCapacity: { _ in nil })
        await assertError(service, future, .futureManifestSchema(BoardManifest.currentSchemaVersion + 1))
    }

    @Test("Schema futuro do board é rejeitado")
    func futureBoardSchemaIsRejected() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        var board = Board()
        board.formatVersion = Board.currentFormatVersion + 1
        let package = try package(at: root, board: board)
        let service = BoardPortablePackageService(availableCapacity: { _ in nil })
        await assertError(service, package, .futureBoardSchema(Board.currentFormatVersion + 1))
    }

    @Test("Schema futuro do workspace é erro na validação e fallback no import")
    func futureWorkspaceSchemaIsRejectedByValidation() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try package(
            at: root, board: Board(), workspace: BoardWorkspaceState(schemaVersion: BoardWorkspaceState.currentSchemaVersion + 1))
        let service = BoardPortablePackageService(availableCapacity: { _ in nil })
        await assertError(service, package, .futureWorkspaceSchema(BoardWorkspaceState.currentSchemaVersion + 1))
        let library = BoardLibrary(rootDirectory: root, packageAvailableCapacity: { _ in nil })
        let result = try await library.importPackageWithReport(from: package)
        #expect(result.workspaceStatus == .futureSchema(BoardWorkspaceState.currentSchemaVersion + 1))
        #expect(try await library.open(result.route)?.workspace == .default)
        let repository = try await library.repository(for: result.route)
        let savedPackage = await repository.packageURL(for: result.boardID)
        let diagnostics = try FileManager.default.contentsOfDirectory(at: savedPackage, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".view-state-corrupt-") }
        #expect(diagnostics.count == 1)
        #expect(
            try Data(contentsOf: try #require(diagnostics.first)) == Data(contentsOf: package.appendingPathComponent("view-state.json")))
        var saved = try #require(await library.open(result.route))
        saved.manifest.contentRevision += 1
        try await repository.save(saved)
        let afterSave = try FileManager.default.contentsOfDirectory(at: savedPackage, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".view-state-corrupt-") }
        #expect(afterSave.count == 1)
    }

    @Test("Limite configurável de itens retorna o limite exato")
    func itemLimitIsExact() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let board = Board(items: [BoardItem(kind: .text, title: "A"), BoardItem(kind: .text, title: "B")])
        let package = try package(at: root, board: board)
        let service = BoardPortablePackageService(limits: BoardPackageLimits(maximumItems: 1), availableCapacity: { _ in nil })
        await assertError(service, package, .tooManyItems(limit: 1))
    }

    @Test("IDs duplicados são rejeitados")
    func duplicateIDsAreRejected() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let package = try package(
            at: root, board: Board(items: [BoardItem(id: id, kind: .text, title: "A"), BoardItem(id: id, kind: .text, title: "B")]))
        let service = BoardPortablePackageService(availableCapacity: { _ in nil })
        await assertError(service, package, .duplicateItemID(id))
    }

    @Test("Posição não finita, parent inválido e payload de arquivo são rejeitados")
    func itemPayloadValidationIsExact() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = BoardPortablePackageService(availableCapacity: { _ in nil })
        let items = root.appendingPathComponent("Items", isDirectory: true)
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        let nonFinite = BoardItem(kind: .text, title: "A", position: BoardPoint(x: .infinity, y: 0))
        await assertBoardError(service, Board(items: [nonFinite]), items, .invalidItemPosition(nonFinite.id))
        let child = BoardItem(kind: .text, title: "A", parentID: UUID())
        await assertBoardError(service, Board(items: [child]), items, .invalidItemParent(child.id))
        let parent = BoardItem(kind: .text, title: "not folder")
        let childOfText = BoardItem(kind: .text, title: "A", parentID: parent.id)
        await assertBoardError(service, Board(items: [parent, childOfText]), items, .invalidItemParent(childOfText.id))
        let folder = BoardItem(kind: .folder, title: "folder", parentID: UUID())
        await assertBoardError(service, Board(items: [folder]), items, .invalidItemParent(folder.id))
        let rootFolder = BoardItem(kind: .folder, title: "root")
        let nestedFolder = BoardItem(kind: .folder, title: "nested", parentID: rootFolder.id)
        await assertBoardError(service, Board(items: [rootFolder, nestedFolder]), items, .invalidItemParent(nestedFolder.id))
        let image = BoardItem(kind: .image, title: "image")
        await assertBoardError(service, Board(items: [image]), items, .missingAsset("\(image.id.uuidString):fileName"))
        let text = BoardItem(kind: .text, title: "text", fileName: "extra.txt")
        await assertBoardError(service, Board(items: [text]), items, .invalidFileName(text.id))
    }

    @Test("Traversal e separator de fileName retornam o item exato")
    func unsafeFileNamesAreRejected() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = BoardPortablePackageService(availableCapacity: { _ in nil })
        for fileName in ["../escape", "folder/asset.png", "folder\\asset.png"] {
            let item = BoardItem(kind: .image, title: "image", fileName: fileName)
            await assertBoardError(service, Board(items: [item]), root, .invalidFileName(item.id))
        }
    }

    @Test("Asset ausente, compartilhado, não referenciado e aninhado retornam cases exatos")
    func assetValidationIsExact() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = BoardPortablePackageService(availableCapacity: { _ in nil })
        let missing = BoardItem(kind: .image, title: "missing", fileName: "missing.png")
        let missingPackage = try package(at: root, board: Board(items: [missing]))
        await assertError(service, missingPackage, .missingAsset("missing.png"))
        let shared = Board(items: [
            BoardItem(kind: .image, title: "A", fileName: "shared.png"), BoardItem(kind: .image, title: "B", fileName: "shared.png"),
        ])
        let sharedPackage = try package(at: root, board: shared)
        try Data([1]).write(to: sharedPackage.appendingPathComponent("Items/shared.png"))
        await assertError(service, sharedPackage, .duplicateAsset("shared.png"))
        let unreferenced = try package(at: root, board: Board())
        try Data([1]).write(to: unreferenced.appendingPathComponent("Items/orphan.bin"))
        await assertError(service, unreferenced, .unreferencedAsset("orphan.bin"))
        let nested = try package(at: root, board: Board())
        try FileManager.default.createDirectory(
            at: nested.appendingPathComponent("Items/nested", isDirectory: true), withIntermediateDirectories: true)
        await assertError(service, nested, .nestedDirectory(nested.appendingPathComponent("Items/nested").standardizedFileURL))
        let incompatible = BoardItem(kind: .image, title: "image", fileName: "note.txt")
        let incompatiblePackage = try package(at: root, board: Board(items: [incompatible]))
        try Data([1]).write(to: incompatiblePackage.appendingPathComponent("Items/note.txt"))
        await assertError(service, incompatiblePackage, .assetKindMismatch(incompatible.id, expected: .image, actual: .text))
        let unknown = BoardItem(kind: .image, title: "image", fileName: "asset.unknown-extension")
        let unknownPackage = try package(at: root, board: Board(items: [unknown]))
        try Data([1]).write(to: unknownPackage.appendingPathComponent("Items/asset.unknown-extension"))
        await assertError(service, unknownPackage, .assetKindMismatch(unknown.id, expected: .image, actual: nil))
    }

    @Test("Symlinks na raiz e no asset são rejeitados")
    func symlinksAreRejected() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = BoardPortablePackageService(availableCapacity: { _ in nil })
        let real = try package(at: root, board: Board())
        let linked = root.appendingPathComponent("linked.mural")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: real)
        await assertError(service, linked, .symlink(linked.standardizedFileURL))
        let asset = BoardItem(kind: .image, title: "image", fileName: "asset.png")
        let package = try package(at: root, board: Board(items: [asset]))
        let outside = root.appendingPathComponent("outside.bin")
        try Data([1]).write(to: outside)
        let assetURL = package.appendingPathComponent("Items/asset.png")
        try FileManager.default.createSymbolicLink(at: assetURL, withDestinationURL: outside)
        await assertError(service, package, .symlink(assetURL.standardizedFileURL))
    }

    @Test("Limites de manifest, board, arquivo, pacote e capacidade são exatas")
    func sizeLimitsAreExact() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let packageURL = try package(at: root, board: Board())
        let service = BoardPortablePackageService(limits: BoardPackageLimits(manifestBytes: 1), availableCapacity: { _ in nil })
        await assertError(service, packageURL, .fileTooLarge(packageURL.appendingPathComponent("manifest.json"), limit: 1))
        let boardPackage = try package(at: root, board: Board())
        let boardService = BoardPortablePackageService(limits: BoardPackageLimits(boardBytes: 1), availableCapacity: { _ in nil })
        await assertError(boardService, boardPackage, .fileTooLarge(boardPackage.appendingPathComponent("board.json"), limit: 1))
        let item = BoardItem(kind: .image, title: "image", fileName: "asset.png")
        let filePackage = try package(at: root, board: Board(items: [item]))
        try Data([1, 2]).write(to: filePackage.appendingPathComponent("Items/asset.png"))
        let fileService = BoardPortablePackageService(limits: BoardPackageLimits(maximumFileBytes: 1), availableCapacity: { _ in nil })
        await assertError(fileService, filePackage, .fileTooLarge(filePackage.appendingPathComponent("Items/asset.png"), limit: 1))
        let packageService = BoardPortablePackageService(
            limits: BoardPackageLimits(maximumPackageBytes: 1), availableCapacity: { _ in nil })
        await assertError(packageService, packageURL, .packageTooLarge(limit: 1))
        let capacityService = BoardPortablePackageService(availableCapacity: { _ in 5 })
        await assertError(capacityService, packageURL, .packageTooLarge(limit: 4))
    }

    @Test("Workspace acima do limite não é tratado como corrupção")
    func oversizedWorkspaceIsRejected() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try package(at: root, board: Board(), workspace: .default)
        try Data(repeating: 1, count: 101).write(to: package.appendingPathComponent("view-state.json"))
        let service = BoardPortablePackageService(
            limits: BoardPackageLimits(boardBytes: 100), availableCapacity: { _ in nil })
        await assertError(
            service, package,
            .fileTooLarge(package.appendingPathComponent("view-state.json"), limit: 100)
        )
    }

    @Test("Entrada raiz inesperada retorna o nome exato")
    func unexpectedRootEntryIsRejected() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try package(at: root, board: Board())
        try Data([1]).write(to: package.appendingPathComponent("unexpected.bin"))
        let service = BoardPortablePackageService(availableCapacity: { _ in nil })
        await assertError(service, package, .unexpectedEntry("unexpected.bin"))
    }

    @Test("Cleanup fora de Transfers é rejeitado")
    func cleanupOutsideTransfersIsRejected() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = BoardPortablePackageService(availableCapacity: { _ in nil })
        let transfers = root.appendingPathComponent("Transfers", isDirectory: true)
        let outside = root.appendingPathComponent("outside.mural", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        await #expect(throws: BoardPortablePackageError.notDescendant(outside)) {
            try await service.cleanup(outside, inside: transfers)
        }
    }

    @Test("Import limpa staging em sucesso e erro")
    func importStagingIsCleaned() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let packageURL = try package(at: root, board: Board())
        let library = BoardLibrary(rootDirectory: root, packageAvailableCapacity: { _ in nil })
        _ = try await library.importPackage(from: packageURL)
        #expect(
            try FileManager.default.contentsOfDirectory(at: await library.importStagingDirectory, includingPropertiesForKeys: nil).isEmpty)
        let invalid = try package(at: root, board: Board())
        try Data("bad".utf8).write(to: invalid.appendingPathComponent("manifest.json"))
        await #expect(throws: BoardLibraryError.self) { _ = try await library.importPackage(from: invalid) }
        #expect(
            try FileManager.default.contentsOfDirectory(at: await library.importStagingDirectory, includingPropertiesForKeys: nil).isEmpty)
    }

    @Test("Preflight rejeita fonte acima do limite antes de copiar")
    func oversizedSourceDoesNotCreateStaging() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try package(at: root, board: Board())
        let payload = Data(repeating: 7, count: 32)
        try payload.write(to: source.appendingPathComponent("Items/payload.bin"))
        let library = BoardLibrary(
            rootDirectory: root.appendingPathComponent("Library", isDirectory: true),
            packageLimits: BoardPackageLimits(maximumPackageBytes: 1),
            packageAvailableCapacity: { _ in nil }
        )
        await #expect(throws: BoardLibraryError.portable(.packageTooLarge(limit: 1))) {
            _ = try await library.importPackage(from: source)
        }
        #expect(
            try FileManager.default.contentsOfDirectory(at: await library.importStagingDirectory, includingPropertiesForKeys: nil).isEmpty)
        #expect(try Data(contentsOf: source.appendingPathComponent("Items/payload.bin")) == payload)
    }

    @Test("Falha beforeSwap e afterSwap não deixa Board parcial")
    func publishFailureLeavesNoPartialBoard() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try package(at: root, board: Board(items: [BoardItem(kind: .text, title: "import")]))
        try Data("corrupt".utf8).write(to: package.appendingPathComponent("view-state.json"))
        for point in [BoardRepositoryFaultPoint.beforeSwap, .afterSwap] {
            let isolatedRoot = root.appendingPathComponent(point.rawValue, isDirectory: true)
            let library = BoardLibrary(
                rootDirectory: isolatedRoot, repositoryFaultInjection: BoardRepositoryFaultInjection(points: [point]),
                packageAvailableCapacity: { _ in nil })
            await #expect(throws: BoardRepositoryError.self) { _ = try await library.importPackage(from: package) }
            #expect(try await library.listSaved().isEmpty)
            let boards = await library.boardsDirectory
            let entries = try FileManager.default.contentsOfDirectory(at: boards, includingPropertiesForKeys: nil)
            #expect(entries.filter { $0.pathExtension == "mural" }.isEmpty)
        }
    }

    private func assertError(_ service: BoardPortablePackageService, _ package: URL, _ expected: BoardPortablePackageError) async {
        do {
            try await service.validate(package)
            Issue.record("expected \(expected), validation succeeded")
        } catch {
            #expect(matchesExpectedCase(error, expected))
        }
    }

    private func assertBoardError(
        _ service: BoardPortablePackageService, _ board: Board, _ items: URL, _ expected: BoardPortablePackageError
    ) async {
        do {
            try await service.validateBoard(board, itemsURL: items)
            Issue.record("expected \(expected), validation succeeded")
        } catch {
            #expect(matchesExpectedCase(error, expected))
        }
    }

    private func jsonObject(at url: URL) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }

    private func matchesExpectedCase(_ error: Error, _ expected: BoardPortablePackageError) -> Bool {
        guard let actual = error as? BoardPortablePackageError else { return false }
        switch (actual, expected) {
        case (.symlink, .symlink), (.nestedDirectory, .nestedDirectory): return true
        default: return actual == expected
        }
    }

    private func snapshot(_ package: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for url in try FileManager.default.contentsOfDirectory(at: package, includingPropertiesForKeys: nil) {
            if url.lastPathComponent == "Items" {
                for asset in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                    result["Items/\(asset.lastPathComponent)"] = try Data(contentsOf: asset)
                }
            } else {
                result[url.lastPathComponent] = try Data(contentsOf: url)
            }
        }
        return result
    }
}

extension BoardRoute {
    fileprivate var id: BoardID? {
        if case .saved(let id) = self { return id }
        return nil
    }
}
