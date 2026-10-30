import Foundation
import Testing

@testable import MuralKit

/// Recuperação de trocas interrompidas e limpeza de restos antigos na primeira listagem.
@Suite("Recuperação de trabalho interrompido")
struct BoardLibraryRecoveryTests {
    private let hour: TimeInterval = 3600
    private let now = Date()

    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MuralRecovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Biblioteca cujo descarte move o pacote para `Lixo/`, em vez do Lixo do Mac.
    private func library(_ directory: URL, failingDiscard: Bool = false) throws -> (BoardLibrary, trash: URL) {
        let trash = directory.appendingPathComponent("Lixo", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let library = BoardLibrary(
            rootDirectory: directory.appendingPathComponent("Library", isDirectory: true),
            discardPackage: { url in
                if failingDiscard { throw CocoaError(.fileWriteNoPermission) }
                try FileManager.default.moveItem(at: url, to: trash.appendingPathComponent(url.lastPathComponent))
            })
        return (library, trash)
    }

    private func age(_ url: URL, hours: TimeInterval) throws {
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-hours * hour)], ofItemAtPath: url.path)
    }

    private func savedID(_ route: BoardRoute) throws -> BoardID {
        guard case .saved(let id) = route else { throw CocoaError(.fileReadUnknown) }
        return id
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    private func names(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    /// Cria um mural e o deixa como a queda o deixaria: pacote ausente, backup no lugar.
    private func boardInBackup(
        _ library: BoardLibrary, ageHours: TimeInterval
    ) async throws -> (id: BoardID, boards: URL, package: URL, backup: URL) {
        let route = try await library.createNamedBoard("Mural")
        let id = try savedID(route)
        let boards = await library.boardsDirectory
        let package = boards.appendingPathComponent("\(id.rawValue.uuidString).mural", isDirectory: true)
        let backup = boards.appendingPathComponent(".\(id.rawValue.uuidString).mural-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.moveItem(at: package, to: backup)
        try age(backup, hours: ageHours)
        return (id, boards, package, backup)
    }

    private func addStaging(copyOf backup: URL, id: BoardID, in boards: URL, dropping missing: String? = nil) throws -> URL {
        let staging = boards.appendingPathComponent(".\(id.rawValue.uuidString).mural-staging-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: backup, to: staging)
        try Data("novo".utf8).write(to: staging.appendingPathComponent("marcador.txt"))
        if let missing { try FileManager.default.removeItem(at: staging.appendingPathComponent(missing)) }
        return staging
    }

    @Test("Sem pacote, o backup parado há mais de um minuto volta ao lugar")
    func backupIsRestored() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (library, trash) = try library(directory)
        let state = try await boardInBackup(library, ageHours: 0.1)

        await library.recoverInterruptedWork(now: now)

        #expect(exists(state.package.appendingPathComponent("manifest.json")))
        #expect(!exists(state.backup))
        #expect(try names(in: trash).isEmpty)
    }

    @Test("Staging completo é o mais novo: vira o pacote e o backup vai para o descarte")
    func completeStagingIsPreferred() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (library, trash) = try library(directory)
        let state = try await boardInBackup(library, ageHours: 0.1)
        let staging = try addStaging(copyOf: state.backup, id: state.id, in: state.boards)

        await library.recoverInterruptedWork(now: now)

        #expect(exists(state.package.appendingPathComponent("marcador.txt")))
        #expect(!exists(staging))
        #expect(try names(in: trash) == [state.backup.lastPathComponent])
    }

    @Test("Staging incompleto é ignorado e o backup volta")
    func incompleteStagingIsIgnored() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (library, trash) = try library(directory)
        let state = try await boardInBackup(library, ageHours: 0.1)
        let staging = try addStaging(copyOf: state.backup, id: state.id, in: state.boards, dropping: "view-state.json")

        await library.recoverInterruptedWork(now: now)

        #expect(exists(state.package.appendingPathComponent("view-state.json")))
        #expect(!exists(state.package.appendingPathComponent("marcador.txt")))
        #expect(exists(staging), "staging recente não é apagado")
        #expect(try names(in: trash).isEmpty)
    }

    @Test("Backup recente (menos de um minuto) e pastas intruder ficam como estão")
    func recentBackupAndIntruderAreUntouched() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (library, _) = try library(directory)
        let state = try await boardInBackup(library, ageHours: 0)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-10)], ofItemAtPath: state.backup.path)
        let intruder = state.boards.appendingPathComponent(".\(state.id.rawValue.uuidString).mural-intruder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: intruder, withIntermediateDirectories: true)
        try age(intruder, hours: 100)
        let before = try names(in: state.boards)

        await library.recoverInterruptedWork(now: now)

        #expect(try names(in: state.boards) == before)
    }

    @Test("Com o pacote presente, backup de 6 horas ou mais vai para o descarte e o mais novo fica")
    func oldBackupGoesToDiscard() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (library, trash) = try library(directory)
        let route = try await library.createNamedBoard("Mural")
        let id = try savedID(route)
        let boards = await library.boardsDirectory
        let uuid = id.rawValue.uuidString
        let old = boards.appendingPathComponent(".\(uuid).mural-backup-\(UUID().uuidString)", isDirectory: true)
        let recent = boards.appendingPathComponent(".\(uuid).mural-backup-\(UUID().uuidString)", isDirectory: true)
        for url in [old, recent] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        try age(old, hours: 7)
        try age(recent, hours: 5)

        await library.recoverInterruptedWork(now: now)

        #expect(try names(in: trash) == [old.lastPathComponent])
        #expect(exists(recent))
        #expect(exists(boards.appendingPathComponent("\(uuid).mural/manifest.json")))
    }

    @Test("Staging antigo com o pacote presente é removido; o recente e o sem pacote ficam")
    func oldStagingIsRemoved() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (library, _) = try library(directory)
        let route = try await library.createNamedBoard("Mural")
        let id = try savedID(route)
        let boards = await library.boardsDirectory
        let old = boards.appendingPathComponent(".\(id.rawValue.uuidString).mural-staging-\(UUID().uuidString)")
        let recent = boards.appendingPathComponent(".\(id.rawValue.uuidString).mural-staging-\(UUID().uuidString)")
        let orphan = boards.appendingPathComponent(".\(UUID().uuidString).mural-staging-\(UUID().uuidString)")
        for url in [old, recent, orphan] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        try age(old, hours: 7)
        try age(recent, hours: 5)
        try age(orphan, hours: 7)

        await library.recoverInterruptedWork(now: now)

        #expect(!exists(old))
        #expect(exists(recent))
        #expect(exists(orphan), "sem o pacote principal, o staging pode ser o único resto do mural")
    }

    @Test("Hard links de backup dentro do pacote saem com 6 horas ou mais")
    func oldHardLinkBackupsAreRemoved() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (library, _) = try library(directory)
        let route = try await library.createNamedBoard("Mural")
        let id = try savedID(route)
        let package = await library.boardsDirectory.appendingPathComponent("\(id.rawValue.uuidString).mural", isDirectory: true)
        let old = package.appendingPathComponent(".board.json.backup-\(UUID().uuidString)")
        let recent = package.appendingPathComponent(".manifest.json.backup-\(UUID().uuidString)")
        try FileManager.default.linkItem(at: package.appendingPathComponent("board.json"), to: old)
        try FileManager.default.linkItem(at: package.appendingPathComponent("manifest.json"), to: recent)
        try age(old, hours: 7)
        try age(recent, hours: 5)

        await library.recoverInterruptedWork(now: now)

        #expect(!exists(old))
        #expect(exists(recent))
        #expect(exists(package.appendingPathComponent("board.json")))
    }

    @Test("Transfers e ImportStaging: 24 horas ou mais saem, o resto fica")
    func oldTransfersAreRemoved() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (library, _) = try library(directory)
        _ = try await library.listSavedReport()  // cria as pastas
        let transfers = await library.transfersDirectory
        let staging = await library.importStagingDirectory
        let oldTransfer = transfers.appendingPathComponent("\(UUID().uuidString).mural")
        let newTransfer = transfers.appendingPathComponent("\(UUID().uuidString).mural")
        let oldStaging = staging.appendingPathComponent("\(UUID().uuidString).mural")
        let newStaging = staging.appendingPathComponent("\(UUID().uuidString).mural")
        for url in [oldTransfer, newTransfer, oldStaging, newStaging] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        try age(oldTransfer, hours: 25)
        try age(newTransfer, hours: 23)
        try age(oldStaging, hours: 25)
        try age(newStaging, hours: 23)
        let again = BoardLibrary(rootDirectory: await library.rootDirectory)

        await again.recoverInterruptedWork(now: now)

        #expect(!exists(oldTransfer) && !exists(oldStaging))
        #expect(exists(newTransfer) && exists(newStaging))
    }

    @Test("A recuperação roda uma vez por instância, na primeira listagem, e o mural recuperado aparece nela")
    func runsOnceAtFirstListing() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (library, _) = try library(directory)
        let state = try await boardInBackup(library, ageHours: 24 * 365)

        let listing = try await library.listSavedReport()
        #expect(listing.entries.map(\.route) == [.saved(state.id)])

        let late = state.boards.appendingPathComponent(".\(UUID().uuidString).mural-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: late, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: late.path)
        _ = try await library.listSavedReport()
        #expect(exists(late), "a segunda listagem não repete a recuperação")
    }

    @Test("Falha no descarte não impede a recuperação nem a listagem")
    func discardFailureDoesNotBlockListing() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (library, _) = try library(directory, failingDiscard: true)
        let state = try await boardInBackup(library, ageHours: 24 * 365)
        _ = try addStaging(copyOf: state.backup, id: state.id, in: state.boards)

        let listing = try await library.listSavedReport()

        #expect(listing.entries.map(\.route) == [.saved(state.id)])
        #expect(exists(state.backup), "o backup não é apagado quando o descarte falha")
    }
}
