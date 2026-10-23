import Foundation
import MuralKit
import Testing

@testable import Mural

/// O carregamento de uma sessão de janela é de voo único: dois pedidos ao mesmo tempo (o painel da barra de menus e a
/// escolha da aba, por exemplo) esperam o mesmo carregamento.
@Suite("Carregamento de uma sessão de janela")
@MainActor
struct BoardWindowSessionLoadTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralSessionLoad-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Dois pedidos ao mesmo tempo abrem uma referência só e montam um modelo só")
    func concurrentLoadsShareOneLoad() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Casa")
        let registry = BoardSessionRegistry(library: library)
        let session = BoardWindowSession(route: route, registry: registry, usesOnDeviceModel: false)

        async let first: Void = session.load()
        async let second: Void = session.load()
        _ = await (first, second)

        #expect(session.model != nil)
        #expect(await registry.ownerCount(for: session.boardID) == 1)

        // Um pedido depois do carregamento não troca o modelo.
        let model = try #require(session.model)
        await session.load()
        #expect(session.model === model)
        #expect(await registry.ownerCount(for: session.boardID) == 1)

        await session.handleWindowWillClose()
        #expect(await registry.ownerCount(for: session.boardID) == 0)
    }

    @Test("Depois de uma falha, um novo pedido carrega de novo em vez de repetir a falha")
    func loadCanBeRetriedAfterFailure() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        _ = try await library.bootstrap()
        let registry = BoardSessionRegistry(library: library)
        // Um mural que ainda não existe: o primeiro carregamento falha.
        let id = BoardID()
        let route = BoardRoute.saved(id)
        let session = BoardWindowSession(route: route, registry: registry, usesOnDeviceModel: false)

        await session.load()
        #expect(session.model == nil)
        #expect(session.error != nil)

        // O mural passa a existir: só uma tentativa nova o encontra.
        let snapshot = BoardRepositorySnapshot(manifest: BoardManifest(id: id, name: "Depois"), board: Board(), workspace: .default)
        try await library.repository(for: route).save(snapshot)

        await session.retryLoad()
        #expect(session.model != nil)
        #expect(session.error == nil)
        await session.handleWindowWillClose()
    }
}
