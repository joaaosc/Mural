import Foundation
import Testing

@testable import MuralKit

/// Excluir mural: o salvo vai para o descarte (o Lixo, no app), o rascunho é descartado, e uma rota que
/// não existe ou um descarte que falha não mexem em nada.
@Suite("Excluir mural")
struct BoardDeletionTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MuralDeletion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Mural salvo excluído sai da lista e da abertura; o pacote vai para o descarte e o vizinho fica")
    func savedBoardGoesToDiscard() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let trash = directory.appendingPathComponent("Lixo", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let discarded = DiscardLog()
        let library = BoardLibrary(
            rootDirectory: directory,
            discardPackage: { url in
                discarded.append(url)
                try FileManager.default.moveItem(at: url, to: trash.appendingPathComponent(url.lastPathComponent))
            })
        let doomed = try await library.createNamedBoard("Excluir")
        let kept = try await library.createNamedBoard("Manter")

        try await library.deleteBoard(doomed)

        let names = try await library.listSaved().map(\.manifest.name)
        #expect(names == ["Manter"])
        await #expect(throws: BoardLibraryError.self) { _ = try await library.open(doomed) }
        #expect(try await library.open(kept)?.manifest.name == "Manter")
        #expect(discarded.urls.count == 1)
        #expect(discarded.urls.first?.pathExtension == "mural", "o descarte recebe o pacote inteiro")
    }

    @Test("Excluir o rascunho de exemplo o descarta, como Descartar rascunho")
    func draftIsDiscarded() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory, discardPackage: { _ in Issue.record("rascunho não vai para o Lixo") })
        let state = try await library.bootstrap()

        try await library.deleteBoard(.welcomeDraft(state.stableWelcomeID))

        #expect(try await library.lifecycleState()?.lifecycle == .discarded)
        #expect(try await library.list().isEmpty)
    }

    @Test("Rota que não existe e a rota da biblioteca são recusadas sem descartar nada")
    func unavailableRoutesAreRefused() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory, discardPackage: { _ in Issue.record("nada a descartar") })
        _ = try await library.bootstrap()

        await #expect(throws: BoardLibraryError.unavailableRoute(.library)) { try await library.deleteBoard(.library) }
        let missing = BoardRoute.saved(BoardID())
        await #expect(throws: BoardLibraryError.unavailableRoute(missing)) { try await library.deleteBoard(missing) }
        let stale = BoardRoute.welcomeDraft(BoardID())
        await #expect(throws: BoardLibraryError.unavailableRoute(stale)) { try await library.deleteBoard(stale) }
    }

    @Test("Se o descarte falha, o mural continua na lista e abre")
    func failedDiscardKeepsBoard() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(
            rootDirectory: directory, discardPackage: { _ in throw CocoaError(.fileWriteNoPermission) })
        let route = try await library.createNamedBoard("Teimoso")

        await #expect(throws: BoardLibraryError.self) { try await library.deleteBoard(route) }

        #expect(try await library.listSaved().map(\.manifest.name) == ["Teimoso"])
        #expect(try await library.open(route)?.manifest.name == "Teimoso")
    }
}

/// Endereços recebidos pelo descarte (chamado fora do ator de teste).
private final class DiscardLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URL] = []

    func append(_ url: URL) {
        lock.withLock { stored.append(url) }
    }

    var urls: [URL] {
        lock.withLock { stored }
    }
}
