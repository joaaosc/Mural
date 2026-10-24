import CoreGraphics
import Foundation
import MuralKit
import Testing

@testable import Mural

@Suite("Culling de renderização do canvas")
@MainActor
struct CanvasRenderCullingTests {
    @Test("Converte a viewport ampliada para coordenadas lógicas")
    func logicalViewportUsesZoom() {
        let result = CanvasRenderCulling.logicalVisibleRect(
            CGRect(x: 200, y: 100, width: 800, height: 600), zoom: 2)

        #expect(result == CGRect(x: 100, y: 50, width: 400, height: 300))
    }

    @Test("Seleciona cartões que cruzam a viewport e preserva exceções")
    func visibleItemsPreserveIntersectionAndExplicitItems() {
        let visible = BoardItem(id: UUID(), kind: .text, title: "Visível", position: BoardPoint(x: 20, y: 20))
        let outside = BoardItem(id: UUID(), kind: .text, title: "Fora", position: BoardPoint(x: 500, y: 500))
        let dragged = BoardItem(id: UUID(), kind: .text, title: "Arrastado", position: BoardPoint(x: 900, y: 900))

        let result = CanvasRenderCulling.visibleItems(
            [visible, outside, dragged],
            in: CGRect(x: 0, y: 0, width: 200, height: 200),
            alwaysInclude: [dragged.id],
            overscan: 0)

        #expect(result.map(\.id) == [visible.id, dragged.id])
    }

    @Test("A margem de pré-carregamento inclui o próximo cartão")
    func overscanIncludesNearEdge() {
        let near = BoardItem(id: UUID(), kind: .text, title: "Próximo", position: BoardPoint(x: 220, y: 20))

        let result = CanvasRenderCulling.visibleItems(
            [near],
            in: CGRect(x: 0, y: 0, width: 200, height: 200),
            overscan: 1)

        #expect(result.map(\.id) == [near.id])
    }

    @Test("O modo completo preserva todos os cartões")
    func forceAllPreservesItems() {
        let items = [
            BoardItem(id: UUID(), kind: .text, title: "Visível", position: BoardPoint(x: 20, y: 20)),
            BoardItem(id: UUID(), kind: .text, title: "Fora", position: BoardPoint(x: 900, y: 900)),
        ]

        #expect(
            CanvasRenderCulling.visibleItems(
                items,
                in: CGRect(x: 0, y: 0, width: 100, height: 100),
                forceAll: true) == items)
    }

    @Test("A troca de viewport espera sair da faixa de histerese")
    func viewportHysteresisAvoidsPixelUpdates() {
        let current = CGRect(x: 0, y: 0, width: 200, height: 200)

        #expect(!CanvasRenderCulling.shouldUpdateViewport(current: current, next: CGRect(x: 20, y: 20, width: 200, height: 200)))
        #expect(CanvasRenderCulling.shouldUpdateViewport(current: current, next: CGRect(x: 60, y: 0, width: 200, height: 200)))
    }
}
