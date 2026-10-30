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

    @Test("Reutiliza os tamanhos exibidos ao selecionar cartões")
    func visibleItemsUseDisplayedSizes() {
        let item = BoardItem(
            id: UUID(), kind: .sticky, title: "Aumentado", position: BoardPoint(x: 140, y: 20), size: BoardSize(width: 80, height: 80))

        let result = CanvasRenderCulling.visibleItems(
            [item],
            in: CGRect(x: 0, y: 0, width: 200, height: 50),
            overscan: 0,
            displayedSizes: [item.id: BoardSize(width: 80, height: 80)])

        #expect(result.map(\.id) == [item.id])
    }

    @Test("Aplica o tamanho transitório de um cartão sem copiar o mapa base")
    func visibleItemsUseTransientSizeOverride() {
        let item = BoardItem(
            id: UUID(), kind: .sticky, title: "Redimensionando", position: BoardPoint(x: 299, y: 20))

        let result = CanvasRenderCulling.visibleItems(
            [item],
            in: CGRect(x: 100, y: 0, width: 200, height: 50),
            overscan: 0,
            displayedSizes: [item.id: BoardSize(width: 0, height: 0)],
            sizeOverride: CanvasRenderCulling.SizeOverride(id: item.id, size: BoardSize(width: 80, height: 80)))

        #expect(result.map(\.id) == [item.id])
    }

    @Test("Seleciona textos livres visíveis e preserva o texto em redimensionamento")
    func visibleFreeTextsPreserveIntersectionAndExplicitTexts() {
        let visible = BoardFreeText(
            id: UUID(), text: "Visível", position: BoardPoint(x: 20, y: 20))
        let outside = BoardFreeText(
            id: UUID(), text: "Fora", position: BoardPoint(x: 500, y: 500))
        let resizing = BoardFreeText(
            id: UUID(), text: "Redimensionando", position: BoardPoint(x: 900, y: 900))

        let result = CanvasRenderCulling.visibleFreeTexts(
            [visible, outside, resizing],
            in: CGRect(x: 0, y: 0, width: 200, height: 200),
            alwaysInclude: [resizing.id],
            overscan: 0)

        #expect(result.map(\.id) == [visible.id, resizing.id])
    }

    @Test("Reutiliza os tamanhos exibidos ao selecionar textos livres")
    func visibleFreeTextsUseDisplayedSizes() {
        let freeText = BoardFreeText(
            id: UUID(), text: "Aumentado", position: BoardPoint(x: 140, y: 20))

        let result = CanvasRenderCulling.visibleFreeTexts(
            [freeText],
            in: CGRect(x: 0, y: 0, width: 200, height: 50),
            overscan: 0,
            displayedSizes: [freeText.id: BoardSize(width: 80, height: 80)])

        #expect(result.map(\.id) == [freeText.id])
    }

    @Test("Aplica o tamanho transitório de um texto livre sem copiar o mapa base")
    func visibleFreeTextsUseTransientSizeOverride() {
        let freeText = BoardFreeText(
            id: UUID(), text: "Redimensionando", position: BoardPoint(x: 299, y: 20))

        let result = CanvasRenderCulling.visibleFreeTexts(
            [freeText],
            in: CGRect(x: 100, y: 0, width: 200, height: 50),
            overscan: 0,
            displayedSizes: [freeText.id: BoardSize(width: 0, height: 0)],
            sizeOverride: CanvasRenderCulling.SizeOverride(id: freeText.id, size: BoardSize(width: 80, height: 80)))

        #expect(result.map(\.id) == [freeText.id])
    }

    @Test("O modo completo preserva todos os textos livres")
    func forceAllPreservesFreeTexts() {
        let freeTexts = [
            BoardFreeText(id: UUID(), text: "Visível", position: BoardPoint(x: 20, y: 20)),
            BoardFreeText(id: UUID(), text: "Fora", position: BoardPoint(x: 900, y: 900)),
        ]

        #expect(
            CanvasRenderCulling.visibleFreeTexts(
                freeTexts,
                in: CGRect(x: 0, y: 0, width: 100, height: 100),
                forceAll: true) == freeTexts)
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

    @Test("A árvore acessível mantém itens distantes, mas suas prévias visuais são recortadas")
    func accessibleItemsKeepIndependentVisualVisibility() {
        let visible = BoardItem(id: UUID(), kind: .text, title: "Visível", position: BoardPoint(x: 20, y: 20))
        let distant = BoardItem(id: UUID(), kind: .text, title: "Distante", position: BoardPoint(x: 2000, y: 2000))
        let text = BoardFreeText(id: UUID(), text: "Texto distante", position: BoardPoint(x: 2000, y: 2000))
        let viewport = CGRect(x: 0, y: 0, width: 200, height: 200)
        let full = snapshot(items: [visible, distant], freeTexts: [text], viewport: viewport, forceAll: true)
        #expect(full.items == [visible, distant])
        #expect(full.freeTexts == [text])
        #expect(full.visualItemIDs == [visible.id])
        #expect(full.visualFreeTextIDs.isEmpty)

        let culled = snapshot(items: [visible, distant], freeTexts: [text], viewport: viewport, forceAll: false)
        #expect(culled.items == [visible])
        #expect(culled.freeTexts.isEmpty)
        #expect(culled.visualItemIDs == full.visualItemIDs)
    }

    @Test("Sem geometria, aguarda o primeiro layout sem construir todas as prévias")
    func initialLayoutPreservesSemanticsAndActiveInteractions() {
        let item = BoardItem(id: UUID(), kind: .text, title: "Cartão", position: BoardPoint(x: 20, y: 20))
        let text = BoardFreeText(id: UUID(), text: "Texto", position: BoardPoint(x: 20, y: 20))
        let pending = snapshot(items: [item], freeTexts: [text], viewport: .zero, forceAll: true)
        #expect(pending.items == [item])
        #expect(pending.freeTexts == [text])
        #expect(pending.visualItemIDs.isEmpty)
        #expect(pending.visualFreeTextIDs.isEmpty)
        let normal = snapshot(items: [item], freeTexts: [text], viewport: .zero, forceAll: false)
        #expect(normal.items.isEmpty)
        #expect(normal.freeTexts.isEmpty)
        let active = snapshot(
            items: [item], freeTexts: [text], viewport: .zero, forceAll: false, alwaysItems: [item.id], alwaysTexts: [text.id])
        #expect(active.items == [item])
        #expect(active.freeTexts == [text])
        #expect(active.visualItemIDs == [item.id])
        #expect(active.visualFreeTextIDs == [text.id])
    }

    @Test("O pré-carregamento cobre a área visível em todas as direções até o limite da histerese")
    func preloadCoversViewportUntilRefresh() {
        let items = (0..<400).map { index in
            BoardItem(
                id: UUID(), kind: .sticky, title: "\(index)", position: BoardPoint(x: Double(index % 20) * 50, y: Double(index / 20) * 50))
        }
        let current = CGRect(x: 500, y: 500, width: 200, height: 100)
        let preloaded = Set(CanvasRenderCulling.visibleItems(items, in: current).map(\.id))
        for dx in [-50.0, 0, 50] {
            for dy in [-25.0, 0, 25] {
                let next = current.offsetBy(dx: dx, dy: dy)
                #expect(!CanvasRenderCulling.shouldUpdateViewport(current: current, next: next))
                let visible = Set(CanvasRenderCulling.visibleItems(items, in: next, overscan: 0).map(\.id))
                #expect(visible.isSubset(of: preloaded))
            }
        }
        #expect(CanvasRenderCulling.shouldUpdateViewport(current: current, next: current.offsetBy(dx: 51, dy: 0)))
    }

    private func snapshot(
        items: [BoardItem], freeTexts: [BoardFreeText], viewport: CGRect, forceAll: Bool, alwaysItems: Set<UUID> = [],
        alwaysTexts: Set<UUID> = []
    ) -> CanvasRenderCulling.Snapshot {
        let key = CanvasRenderCulling.Key(
            boardID: BoardID(), generation: 1, boardRevision: 1, renderViewport: viewport, alwaysRendered: alwaysItems,
            alwaysRenderedFreeTexts: alwaysTexts, forceAll: forceAll, resizingItemID: nil, resizingFreeTextID: nil, resizingSize: nil)
        return CanvasRenderCulling.Cache().content(
            for: key, items: items, freeTexts: freeTexts, viewport: viewport, alwaysRendered: alwaysItems,
            alwaysRenderedFreeTexts: alwaysTexts, forceAll: forceAll, itemSizes: [:], freeTextSizes: [:])
    }

    @Test("Zoom recalcula a viewport lógica sem abrir o mural inteiro")
    func viewportAfterZoomUsesCompensatedVisibleRect() {
        let current = CGRect(x: 10, y: 20, width: 800, height: 600)

        let result = CanvasRenderCulling.viewportAfterZoom(
            current: current,
            visibleRect: CGRect(x: 250, y: 125, width: 1_000, height: 750),
            zoom: 1.25)

        #expect(result == CGRect(x: 200, y: 100, width: 800, height: 600))
    }

    @Test("Zoom sem geometria conserva o último recorte conhecido")
    func viewportAfterZoomKeepsCurrentViewportWithoutGeometry() {
        let current = CGRect(x: 10, y: 20, width: 800, height: 600)

        let result = CanvasRenderCulling.viewportAfterZoom(
            current: current,
            visibleRect: .zero,
            zoom: 1.25)

        #expect(result == current)
    }

    @Test("O cache invalida o culling quando a revisão do mural muda")
    func cacheInvalidatesForBoardRevision() {
        let cache = CanvasRenderCulling.Cache()
        let item = BoardItem(id: UUID(), kind: .text, title: "Primeiro", position: BoardPoint(x: 20, y: 20))
        let replacement = BoardItem(id: item.id, kind: .text, title: "Atualizado", position: item.position)
        let viewport = CGRect(x: 0, y: 0, width: 200, height: 200)
        let key = CanvasRenderCulling.Key(
            boardID: BoardID(),
            generation: 1,
            boardRevision: 1,
            renderViewport: viewport,
            alwaysRendered: [],
            alwaysRenderedFreeTexts: [],
            forceAll: false,
            resizingItemID: nil,
            resizingFreeTextID: nil,
            resizingSize: nil)

        let first = cache.content(
            for: key,
            items: [item],
            freeTexts: [],
            viewport: viewport,
            alwaysRendered: [],
            alwaysRenderedFreeTexts: [],
            forceAll: false,
            itemSizes: [:],
            freeTextSizes: [:])
        let reused = cache.content(
            for: key,
            items: [replacement],
            freeTexts: [],
            viewport: viewport,
            alwaysRendered: [],
            alwaysRenderedFreeTexts: [],
            forceAll: false,
            itemSizes: [:],
            freeTextSizes: [:])

        #expect(first.items == reused.items)

        let nextKey = CanvasRenderCulling.Key(
            boardID: key.boardID,
            generation: key.generation,
            boardRevision: 2,
            renderViewport: key.renderViewport,
            alwaysRendered: key.alwaysRendered,
            alwaysRenderedFreeTexts: key.alwaysRenderedFreeTexts,
            forceAll: key.forceAll,
            resizingItemID: key.resizingItemID,
            resizingFreeTextID: key.resizingFreeTextID,
            resizingSize: key.resizingSize)
        let refreshed = cache.content(
            for: nextKey,
            items: [replacement],
            freeTexts: [],
            viewport: viewport,
            alwaysRendered: [],
            alwaysRenderedFreeTexts: [],
            forceAll: false,
            itemSizes: [:],
            freeTextSizes: [:])

        #expect(refreshed.items == [replacement])
    }
}
