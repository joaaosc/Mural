import CoreGraphics
import Foundation
import MuralKit

/// Seleção geométrica dos elementos que precisam existir na árvore do canvas agora.
/// O frame do `ScrollView` continua cobrindo o mural inteiro; só os elementos fora da
/// janela (com uma margem de pré-carregamento) deixam de construir subviews SwiftUI.
enum CanvasRenderCulling {
    static func logicalVisibleRect(_ visibleRect: CGRect, zoom: CGFloat) -> CGRect {
        guard zoom.isFinite, zoom > 0,
            visibleRect.minX.isFinite, visibleRect.minY.isFinite,
            visibleRect.width.isFinite, visibleRect.height.isFinite,
            !visibleRect.isEmpty
        else { return .zero }

        return CGRect(
            x: visibleRect.minX / zoom,
            y: visibleRect.minY / zoom,
            width: visibleRect.width / zoom,
            height: visibleRect.height / zoom)
    }

    /// Só troca a seleção renderizada quando a viewport sai da faixa de pré-carregamento.
    /// Isso evita refazer a árvore a cada pixel de rolagem, mas garante que a próxima
    /// região já esteja pronta antes de entrar na tela.
    static func shouldUpdateViewport(current: CGRect, next: CGRect) -> Bool {
        guard !next.isEmpty else { return false }
        guard !current.isEmpty else { return true }
        guard abs(current.width - next.width) <= 1, abs(current.height - next.height) <= 1 else { return true }

        let hysteresis = current.insetBy(dx: -max(current.width * 0.25, 1), dy: -max(current.height * 0.25, 1))
        return !hysteresis.contains(next)
    }

    static func visibleItems(
        _ items: [BoardItem],
        in logicalViewport: CGRect,
        alwaysInclude: Set<UUID> = [],
        overscan: CGFloat = 1,
        forceAll: Bool = false
    ) -> [BoardItem] {
        guard !forceAll, !logicalViewport.isEmpty,
            logicalViewport.minX.isFinite, logicalViewport.minY.isFinite,
            logicalViewport.width.isFinite, logicalViewport.height.isFinite,
            overscan.isFinite, overscan >= 0
        else { return items }

        let extraWidth = max(logicalViewport.width, 1) * overscan
        let extraHeight = max(logicalViewport.height, 1) * overscan
        let renderRect = logicalViewport.insetBy(dx: -extraWidth, dy: -extraHeight)
        return items.filter { item in
            alwaysInclude.contains(item.id) || frame(of: item).intersects(renderRect)
        }
    }

    static func visibleFreeTexts(
        _ freeTexts: [BoardFreeText],
        in logicalViewport: CGRect,
        alwaysInclude: Set<UUID> = [],
        overscan: CGFloat = 1,
        forceAll: Bool = false
    ) -> [BoardFreeText] {
        guard !forceAll, !logicalViewport.isEmpty,
            logicalViewport.minX.isFinite, logicalViewport.minY.isFinite,
            logicalViewport.width.isFinite, logicalViewport.height.isFinite,
            overscan.isFinite, overscan >= 0
        else { return freeTexts }

        let extraWidth = max(logicalViewport.width, 1) * overscan
        let extraHeight = max(logicalViewport.height, 1) * overscan
        let renderRect = logicalViewport.insetBy(dx: -extraWidth, dy: -extraHeight)
        return freeTexts.filter { freeText in
            alwaysInclude.contains(freeText.id) || frame(of: freeText).intersects(renderRect)
        }
    }

    private static func frame(of item: BoardItem) -> CGRect {
        let size = BoardLayout.size(of: item)
        return CGRect(
            x: item.position.x,
            y: item.position.y,
            width: size.width,
            height: size.height)
    }

    private static func frame(of freeText: BoardFreeText) -> CGRect {
        let size = BoardLayout.size(of: freeText)
        return CGRect(
            x: freeText.position.x,
            y: freeText.position.y,
            width: size.width,
            height: size.height)
    }
}
