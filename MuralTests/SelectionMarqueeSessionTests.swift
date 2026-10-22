import CoreGraphics
import Foundation
import MuralKit
import Testing

@testable import Mural

/// A sessão recebe a marcação inteira do retângulo de Shift + arrastar.
@Suite("Marcação por retângulo na sessão")
@MainActor
struct SelectionMarqueeSessionTests {
    private func makeReady(_ session: BoardWindowSession) async {
        await session.load()
        let metrics = CanvasScrollMetrics(
            contentOffset: .zero, containerSize: CGSize(width: 900, height: 700),
            contentSize: CGSize(width: 3_400, height: 2_800))
        for _ in 0..<3 where session.restorationPhase != .ready {
            session.restoreCanvas(boardID: session.boardID, generation: session.presentationGeneration, metrics: metrics)
        }
        #expect(session.restorationPhase == .ready)
    }

    @Test("Marca só os cartões do nível aberto; o de dentro da pasta fica de fora")
    func selectsOnlyOpenLevel() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralMarquee-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Retângulo")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        await makeReady(session)
        let model = try #require(session.model)
        let a = try #require(model.importText("A"))
        let b = try #require(model.importText("B"))
        let folder = model.createFolder(named: "Pasta")
        let inside = try #require(model.importText("Dentro"))
        model.moveIntoFolder(inside.id, folderID: folder.id)

        session.select([a.id, b.id, inside.id])
        #expect(session.currentSelection == [a.id, b.id])
        #expect(session.isSelecting, "com cartões marcados, a barra do seletor aparece")

        session.select([])
        #expect(session.currentSelection.isEmpty)
        #expect(!session.isSelecting)
        await session.handleWindowWillClose()
    }
}
