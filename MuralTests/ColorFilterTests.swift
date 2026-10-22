import CoreGraphics
import Foundation
import MuralKit
import Testing

@testable import Mural

/// Destaque por cor: só a cor escolhida fica normal, junto com o filtro de tipo valem os dois, e o filtro
/// some ao trocar de nível, como cada nível começa sem filtro.
@Suite("Filtro por cor")
@MainActor
struct ColorFilterTests {
    private func card(_ kind: ItemKind, _ color: TagColor? = nil) -> BoardItem {
        BoardItem(kind: kind, title: "\(kind)", colorTag: color)
    }

    @Test("Só a cor escolhida fica normal; sem filtro, nada esmaece")
    func colorFilterDimsOtherColors() {
        let red = card(.text, .red)
        let blue = card(.text, .blue)
        let plain = card(.text)
        #expect(BoardFilter.emphasis(for: plain, kind: nil, color: nil) == 1)
        #expect(BoardFilter.emphasis(for: red, kind: nil, color: .red) == 1)
        #expect(BoardFilter.emphasis(for: blue, kind: nil, color: .red) == 0.25)
        #expect(BoardFilter.emphasis(for: plain, kind: nil, color: .red) == 0.25, "sem cor também esmaece")
    }

    @Test("Tipo e cor juntos: fica normal só quem passa nos dois")
    func kindAndColorCombine() {
        let redNote = card(.text, .red)
        let redList = card(.checklist, .red)
        let blueNote = card(.text, .blue)
        #expect(BoardFilter.emphasis(for: redNote, kind: .notes, color: .red) == 1)
        #expect(BoardFilter.emphasis(for: redList, kind: .notes, color: .red) == 0.25)
        #expect(BoardFilter.emphasis(for: blueNote, kind: .notes, color: .red) == 0.25)
        // O mural usa a mesma regra; o cartão arrastado continua sem esmaecer.
        let focus = BoardFocus(dragged: blueNote.id, filter: .notes, colorFilter: .red)
        #expect(focus.emphasis(for: blueNote) == 1)
        #expect(BoardFocus(colorFilter: .red).emphasis(for: blueNote) == 0.25)
        #expect(BoardFocus(colorFilter: .red).layer(for: blueNote) == 0, "o esmaecido fica atrás")
    }

    @Test("Entrar numa pasta tira o filtro de cor; mudar só o filtro de tipo, não")
    func colorFilterResetsWithLevel() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralColorFilter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let session = BoardWindowSession(
            route: try await library.createNamedBoard("Filtro"), registry: BoardSessionRegistry(library: library))
        await session.load()
        let metrics = CanvasScrollMetrics(
            contentOffset: .zero, containerSize: CGSize(width: 900, height: 700),
            contentSize: CGSize(width: 3_400, height: 2_800))
        for _ in 0..<3 where session.restorationPhase != .ready {
            session.restoreCanvas(boardID: session.boardID, generation: session.presentationGeneration, metrics: metrics)
        }
        let folderID = try #require(session.createFolder(named: "Pasta"))
        session.setNavigation(path: [], filter: nil)

        session.colorFilter = .green
        session.setNavigation(path: [], filter: .notes)
        #expect(session.colorFilter == .green, "trocar o tipo no mesmo nível mantém a cor")
        session.setNavigation(path: [.collection(folderID)], filter: nil)
        #expect(session.colorFilter == nil, "cada nível começa sem filtro")
        await session.handleWindowWillClose()
    }
}
