import Foundation
import Testing

@testable import MuralKit

/// Guarda o que a biblioteca descarta sozinha.
final class DiscardRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    var discarded: [String] { lock.withLock { urls.map(\.lastPathComponent) } }
    func record(_ url: URL) { lock.withLock { urls.append(url) } }
}

@Suite("Retenção de cópias de segurança")
struct BackupRetentionTests {
    private let board = BoardID()

    private func name(_ board: BoardID, _ stamp: String) -> String { "\(board.rawValue.uuidString)-\(stamp).mural" }

    @Test("Com 4 cópias, sobram as 3 mais novas e a mais antiga vai ao descarte")
    func keepsNewestThree() {
        let stamps = ["20260103T120000Z", "20260101T120000Z", "20260104T120000Z", "20260102T120000Z"]
        let names = stamps.map { name(board, $0) }
        #expect(BackupRetention.obsolete(names: names, board: board) == [name(board, "20260101T120000Z")])
        #expect(BackupRetention.obsolete(names: Array(names.prefix(3)), board: board).isEmpty)
    }

    @Test("Nomes fora do padrão e cópias de outros murais ficam intocados")
    func ignoresOtherNames() {
        let other = BoardID()
        let foreign = [
            "notas.txt", "\(board.rawValue.uuidString).mural", "\(board.rawValue.uuidString)-ontem.mural",
            "\(board.rawValue.uuidString)-20260101T120000Z.mural.old", "\(board.rawValue.uuidString)-2026010AT120000Z.mural",
            name(other, "20250101T120000Z"),
        ]
        let own = (1...4).map { name(board, "2026010\($0)T120000Z") }
        #expect(BackupRetention.obsolete(names: foreign + own, board: board) == [own[0]])
        #expect(BackupRetention.all(names: foreign + own, board: board) == own)
    }

    @Test("Pela pasta: descarta só as antigas do mural e ignora pasta ausente")
    func prunesDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MuralRetention-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let names = (1...5).map { name(board, "2026010\($0)T120000Z") } + ["solto.mural"]
        for item in names {
            try FileManager.default.createDirectory(at: directory.appendingPathComponent(item), withIntermediateDirectories: true)
        }

        let recorder = DiscardRecorder()
        BackupRetention.prune(board, in: directory, keeping: 3, discard: recorder.record)
        #expect(recorder.discarded == [names[0], names[1]])

        let all = DiscardRecorder()
        BackupRetention.discardAll(of: board, in: directory, discard: all.record)
        #expect(all.discarded == Array(names[0..<5]))

        BackupRetention.discardAll(of: board, in: directory.appendingPathComponent("nao-existe"), discard: all.record)
    }

    @Test("backupPackage manda ao descarte a cópia mais antiga ao passar de 3")
    func libraryPrunesAfterBackup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MuralRetention-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = DiscardRecorder()
        let library = BoardLibrary(rootDirectory: root, discardPackage: recorder.record)
        let route = try await library.createNamedBoard("Original")
        let backups = root.appendingPathComponent("Backups", isDirectory: true)
        let start = Date(timeIntervalSince1970: 1_792_497_600)

        var created: [URL] = []
        for minute in 0..<4 {
            created.append(try await library.backupPackage(route, to: backups, now: start.addingTimeInterval(Double(minute) * 60)))
            #expect(recorder.discarded.count == max(0, minute - 2))
        }
        #expect(recorder.discarded == [created[0].lastPathComponent])
    }
}

@Suite("Prévias órfãs")
struct OrphanPreviewsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let alive = UUID()
    private let gone = UUID()

    @Test("Apaga só UUID desconhecido e com mais de 24 h; o resto fica")
    func rule() {
        let old = now.addingTimeInterval(-25 * 3600)
        let recent = now.addingTimeInterval(-23 * 3600)
        let folders: [(name: String, modified: Date?)] = [
            (alive.uuidString, old), (gone.uuidString, old), (UUID().uuidString, recent), (UUID().uuidString, nil),
            ("Outros", old), ("\(gone.uuidString)-x", old),
        ]
        #expect(OrphanPreviews.staleFolders(folders, keeping: [alive], now: now) == [gone.uuidString])
    }

    @Test("Pela pasta: remove a órfã antiga e mantém arquivos soltos, nomes estranhos e murais vivos")
    func cleansDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MuralOrphans-\(UUID())", isDirectory: true)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        let fresh = UUID()
        for name in [alive.uuidString, gone.uuidString, fresh.uuidString, "Outros"] {
            try fileManager.createDirectory(at: directory.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try Data().write(to: directory.appendingPathComponent(UUID().uuidString))
        let old = Date().addingTimeInterval(-48 * 3600)
        for name in [alive.uuidString, gone.uuidString, "Outros"] {
            try fileManager.setAttributes([.modificationDate: old], ofItemAtPath: directory.appendingPathComponent(name).path)
        }

        OrphanPreviews.clean(in: directory, keeping: [alive])

        let left = Set(try fileManager.contentsOfDirectory(atPath: directory.path))
        #expect(!left.contains(gone.uuidString))
        #expect(left.contains(alive.uuidString) && left.contains(fresh.uuidString) && left.contains("Outros"))
        #expect(left.count == 4)
    }
}
