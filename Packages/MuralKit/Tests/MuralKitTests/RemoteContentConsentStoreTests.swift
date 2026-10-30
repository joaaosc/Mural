import Foundation
import Testing

@testable import MuralKit

@Suite("Permissão de conteúdo da internet")
struct RemoteContentConsentStoreTests {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RemoteContent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Sem arquivo, nada está bloqueado")
    func startsEmpty() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(!RemoteContentConsentStore(directory: directory).isBlocked(BoardID()))
    }

    @Test("block, allow e forget mudam o estado e persistem")
    func roundTrip() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = BoardID()
        let second = BoardID()
        var store = RemoteContentConsentStore(directory: directory)
        store.block(first)
        store.block(second)
        #expect(store.isBlocked(first))

        var reloaded = RemoteContentConsentStore(directory: directory)
        #expect(reloaded.isBlocked(first) && reloaded.isBlocked(second))
        reloaded.allow(first)
        reloaded.forget(second)
        #expect(!reloaded.isBlocked(first) && !reloaded.isBlocked(second))

        let final = RemoteContentConsentStore(directory: directory)
        #expect(!final.isBlocked(first) && !final.isBlocked(second))
    }

    @Test("Arquivo ilegível vale como vazio e pode ser regravado")
    func corruptedFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(RemoteContentConsentStore.fileName)
        try Data("isto não é JSON".utf8).write(to: file)
        var store = RemoteContentConsentStore(directory: directory)
        let id = BoardID()
        #expect(!store.isBlocked(id))
        store.block(id)
        #expect(RemoteContentConsentStore(directory: directory).isBlocked(id))
    }

    @Test("Pasta que ainda não existe é criada na primeira gravação")
    func createsDirectory() throws {
        let parent = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let directory = parent.appendingPathComponent("nova", isDirectory: true)
        var store = RemoteContentConsentStore(directory: directory)
        let id = BoardID()
        store.block(id)
        #expect(RemoteContentConsentStore(directory: directory).isBlocked(id))
    }

    @Test("Permitir ou esquecer um mural desconhecido não grava arquivo")
    func unknownBoardDoesNotWrite() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var store = RemoteContentConsentStore(directory: directory)
        store.allow(BoardID())
        store.forget(BoardID())
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(RemoteContentConsentStore.fileName).path))
    }
}
