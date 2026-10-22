import CoreGraphics
import Foundation
import MuralKit
import Testing

@testable import Mural

/// Cor pela barra do seletor: pinta só os cartões marcados do nível aberto, com uma gravação, e tira a cor.
@Suite("Cor nos cartões marcados")
@MainActor
struct SelectionColorTests {
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

    @Test("Pinta os marcados, deixa os outros, grava e tira a cor; a marcação continua")
    func colorsOnlyMarkedCards() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralSelectionColor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Seleção")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        await makeReady(session)
        let a = try #require(session.model?.importText("A"))
        let b = try #require(session.model?.importText("B"))
        let c = try #require(session.model?.importText("C"))
        session.toggleSelection(a.id)
        session.toggleSelection(b.id)

        session.colorSelection(.purple)
        #expect(session.model?.item(id: a.id)?.colorTag == .purple)
        #expect(session.model?.item(id: b.id)?.colorTag == .purple)
        #expect(session.model?.item(id: c.id)?.colorTag == nil, "o cartão não marcado fica como estava")
        #expect(session.currentSelection == [a.id, b.id])

        await session.flushAndPrepareToLeave()
        #expect(try await library.open(route)?.board.item(id: b.id)?.colorTag == .purple, "a cor foi gravada")

        session.colorSelection(nil)
        #expect(session.model?.item(id: a.id)?.colorTag == nil)
        #expect(session.model?.item(id: b.id)?.colorTag == nil)
        await session.handleWindowWillClose()
    }
}
