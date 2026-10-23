import CoreGraphics
import Foundation
import MuralKit
import Testing

@testable import Mural

@Suite("Post-it solto na pasta, pela sessão")
@MainActor
struct StickyPlacementSessionTests {
    private func makeSession(directory: URL) async throws -> (BoardWindowSession, BoardModel, UUID) {
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Pastas")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        try await makeReady(session)
        let model = try #require(session.model)
        let folder = model.createFolder(named: "Casa")
        let sticky = model.createSticky(into: folder.id)
        return (session, model, sticky.id)
    }

    private func makeReady(_ session: BoardWindowSession) async throws {
        await session.load()
        let metrics = CanvasScrollMetrics(
            contentOffset: .zero,
            containerSize: CGSize(width: 900, height: 700),
            contentSize: CGSize(width: 3_400, height: 2_800))
        session.restoreCanvas(boardID: session.boardID, generation: session.presentationGeneration, metrics: metrics)
        let target = session.zoom.scrollRequest?.point ?? .zero
        let reached = CanvasScrollMetrics(
            contentOffset: target,
            containerSize: metrics.containerSize,
            contentSize: metrics.contentSize,
            contentInsets: metrics.contentInsets)
        for _ in 0..<3 where session.restorationPhase != .ready {
            session.restoreCanvas(boardID: session.boardID, generation: session.presentationGeneration, metrics: reached)
        }
        #expect(session.restorationPhase == .ready)
    }

    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralStickyPlacement-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Soltar pela sessão grava o lugar do post-it no modelo")
    func recordsThePlace() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (session, model, id) = try await makeSession(directory: directory)
        #expect(model.item(id: id)?.folderPosition == nil, "o post-it novo, sem lugar à vista, entra nas colunas")
        session.placeInFolder(id, at: BoardPoint(x: -60, y: 240))
        #expect(model.item(id: id)?.folderPosition == BoardPoint(x: -60, y: 240))
        #expect(model.item(id: id)?.isPlacedInFolder == true)
        await session.handleWindowWillClose()
    }

    @Test("Com a sessão fechada, nada muda")
    func closedSession() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (session, model, id) = try await makeSession(directory: directory)
        await session.handleWindowWillClose()
        session.placeInFolder(id, at: BoardPoint(x: -60, y: 240))
        #expect(model.item(id: id)?.folderPosition == nil)
    }
}
