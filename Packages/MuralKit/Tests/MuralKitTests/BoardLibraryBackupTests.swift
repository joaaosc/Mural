import Foundation
import Testing

@testable import MuralKit

@Suite("Cópia de segurança do pacote")
struct BoardLibraryBackupTests {
    private func temporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralBackup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Um mural salvo com uma pasta e uma imagem de verdade em `Items/`.
    private func boardWithImage(in library: BoardLibrary) async throws -> (route: BoardRoute, id: BoardID, board: Board) {
        let route = try await library.createNamedBoard("Original")
        guard case .saved(let id) = route else { throw BoardLibraryError.unavailableRoute(route) }
        let repository = try await library.repository(for: route)
        let folder = UUID()
        let board = Board(items: [
            BoardItem(id: folder, kind: .folder, title: "Assets", position: BoardPoint(x: 1, y: 2)),
            BoardItem(
                id: UUID(), kind: .image, title: "Image", parentID: folder, position: BoardPoint(x: 3, y: 4), fileName: "image.png"),
        ])
        try await repository.save(
            BoardRepositorySnapshot(
                manifest: BoardManifest(id: id, name: "Original", contentRevision: 1), board: board,
                workspace: BoardWorkspaceState(contentRevision: 1)))
        let items = await repository.packageURL(for: id).appendingPathComponent("Items", isDirectory: true)
        try Data([1, 2, 3, 4]).write(to: items.appendingPathComponent("image.png"))
        return (route, id, board)
    }

    private let moment = Date(timeIntervalSince1970: 1_792_497_600)

    @Test("A cópia fica em <uuid>-<data>.mural, completa, e o mural de origem não muda")
    func backupIsACompletePackage() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = BoardLibrary(rootDirectory: root)
        let (route, id, board) = try await boardWithImage(in: library)
        let backups = root.appendingPathComponent("Backups", isDirectory: true)

        let backup = try await library.backupPackage(route, to: backups, now: moment)

        #expect(backup.deletingLastPathComponent().standardizedFileURL == backups.standardizedFileURL)
        #expect(backup.lastPathComponent == "\(id.rawValue.uuidString)-20261020T120000Z.mural")
        for name in ["manifest.json", "board.json", "view-state.json", "Items/image.png"] {
            #expect(FileManager.default.fileExists(atPath: backup.appendingPathComponent(name).path), "falta \(name)")
        }
        #expect(try Data(contentsOf: backup.appendingPathComponent("Items/image.png")) == Data([1, 2, 3, 4]))

        // Sem pasta de passagem sobrando, e o mural de origem continua inteiro e gravável.
        let names = try FileManager.default.contentsOfDirectory(atPath: backups.path)
        #expect(names == [backup.lastPathComponent])
        #expect(try #require(await library.open(route)).board == board)

        // A cópia volta a ser um mural completo.
        let imported = try await library.importPackage(from: backup)
        #expect(try #require(await library.open(imported)).board == board)
    }

    @Test("Duas cópias em momentos diferentes ficam lado a lado; no mesmo segundo a segunda é recusada")
    func backupsDoNotOverwrite() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = BoardLibrary(rootDirectory: root)
        let (route, _, _) = try await boardWithImage(in: library)
        let backups = root.appendingPathComponent("Backups", isDirectory: true)

        let first = try await library.backupPackage(route, to: backups, now: moment)
        let second = try await library.backupPackage(route, to: backups, now: moment.addingTimeInterval(60))
        #expect(first != second)
        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))

        await #expect(throws: BoardLibraryError.self) {
            _ = try await library.backupPackage(route, to: backups, now: moment)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: backups.path).count == 2, "a primeira cópia fica intacta")
    }

    @Test("A rota da biblioteca não tem pacote e não cria nada")
    func libraryRouteHasNoPackage() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = BoardLibrary(rootDirectory: root)
        let backups = root.appendingPathComponent("Backups", isDirectory: true)

        await #expect(throws: BoardLibraryError.unavailableRoute(.library)) {
            _ = try await library.backupPackage(.library, to: backups)
        }
        #expect(!FileManager.default.fileExists(atPath: backups.path))
    }
}
