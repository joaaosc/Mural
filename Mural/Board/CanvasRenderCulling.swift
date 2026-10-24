import CoreGraphics
import Foundation
import MuralKit

/// Seleção geométrica dos elementos que precisam existir na árvore do canvas agora.
/// O frame do `ScrollView` continua cobrindo o mural inteiro; só os elementos fora da
/// janela (com uma margem de pré-carregamento) deixam de construir subviews SwiftUI.
enum CanvasRenderCulling {
    struct SizeOverride: Equatable {
        let id: UUID
        let size: BoardSize
    }

    struct Key: Equatable {
        let boardID: BoardID
        let generation: UInt64
        let boardRevision: UInt64
        let renderViewport: CGRect
        let alwaysRendered: Set<UUID>
        let alwaysRenderedFreeTexts: Set<UUID>
        let forceAll: Bool
        let resizingItemID: UUID?
        let resizingFreeTextID: UUID?
        let resizingSize: BoardSize?
    }

    struct Snapshot {
        let key: Key
        let items: [BoardItem]
        let freeTexts: [BoardFreeText]
    }

    final class Cache {
        private var snapshot: Snapshot?

        func content(
            for key: Key,
            items: [BoardItem],
            freeTexts: [BoardFreeText],
            viewport: CGRect,
            alwaysRendered: Set<UUID>,
            alwaysRenderedFreeTexts: Set<UUID>,
            forceAll: Bool,
            itemSizes: [UUID: BoardSize],
            freeTextSizes: [UUID: BoardSize],
            itemSizeOverride: SizeOverride? = nil,
            freeTextSizeOverride: SizeOverride? = nil
        ) -> (items: [BoardItem], freeTexts: [BoardFreeText]) {
            if let snapshot, snapshot.key == key {
                return (snapshot.items, snapshot.freeTexts)
            }
            let content: (items: [BoardItem], freeTexts: [BoardFreeText])
            if viewport.isEmpty {
                content = (items, freeTexts)
            } else {
                content = (
                    visibleItems(
                        items,
                        in: viewport,
                        alwaysInclude: alwaysRendered,
                        forceAll: forceAll,
                        displayedSizes: itemSizes,
                        sizeOverride: itemSizeOverride),
                    visibleFreeTexts(
                        freeTexts,
                        in: viewport,
                        alwaysInclude: alwaysRenderedFreeTexts,
                        forceAll: forceAll,
                        displayedSizes: freeTextSizes,
                        sizeOverride: freeTextSizeOverride
                    )
                )
            }
            snapshot = Snapshot(key: key, items: content.items, freeTexts: content.freeTexts)
            return content
        }
    }

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
        forceAll: Bool = false,
        displayedSizes: [UUID: BoardSize] = [:],
        sizeOverride: SizeOverride? = nil
    ) -> [BoardItem] {
        guard !forceAll, !logicalViewport.isEmpty,
            logicalViewport.minX.isFinite, logicalViewport.minY.isFinite,
            logicalViewport.width.isFinite, logicalViewport.height.isFinite,
            overscan.isFinite, overscan >= 0
        else { return items }

        let extraWidth = max(logicalViewport.width, 1) * overscan
        let extraHeight = max(logicalViewport.height, 1) * overscan
        let renderRect = logicalViewport.insetBy(dx: -extraWidth, dy: -extraHeight)
        var visible: [BoardItem] = []
        visible.reserveCapacity(min(items.count, 128))
        for item in items {
            if alwaysInclude.contains(item.id)
                || frame(of: item, displayedSize: displayedSizes[item.id], sizeOverride: sizeOverride).intersects(renderRect)
            {
                visible.append(item)
            }
        }
        return visible
    }

    static func visibleFreeTexts(
        _ freeTexts: [BoardFreeText],
        in logicalViewport: CGRect,
        alwaysInclude: Set<UUID> = [],
        overscan: CGFloat = 1,
        forceAll: Bool = false,
        displayedSizes: [UUID: BoardSize] = [:],
        sizeOverride: SizeOverride? = nil
    ) -> [BoardFreeText] {
        guard !forceAll, !logicalViewport.isEmpty,
            logicalViewport.minX.isFinite, logicalViewport.minY.isFinite,
            logicalViewport.width.isFinite, logicalViewport.height.isFinite,
            overscan.isFinite, overscan >= 0
        else { return freeTexts }

        let extraWidth = max(logicalViewport.width, 1) * overscan
        let extraHeight = max(logicalViewport.height, 1) * overscan
        let renderRect = logicalViewport.insetBy(dx: -extraWidth, dy: -extraHeight)
        var visible: [BoardFreeText] = []
        visible.reserveCapacity(min(freeTexts.count, 128))
        for freeText in freeTexts {
            if alwaysInclude.contains(freeText.id)
                || frame(of: freeText, displayedSize: displayedSizes[freeText.id], sizeOverride: sizeOverride).intersects(renderRect)
            {
                visible.append(freeText)
            }
        }
        return visible
    }

    private static func frame(
        of item: BoardItem, displayedSize: BoardSize? = nil, sizeOverride: SizeOverride? = nil
    ) -> CGRect {
        let size: BoardSize
        if let sizeOverride, sizeOverride.id == item.id {
            size = sizeOverride.size
        } else {
            size = displayedSize ?? boardSize(of: item)
        }
        return CGRect(
            x: item.position.x,
            y: item.position.y,
            width: size.width,
            height: size.height)
    }

    private static func frame(
        of freeText: BoardFreeText, displayedSize: BoardSize? = nil, sizeOverride: SizeOverride? = nil
    ) -> CGRect {
        let size: BoardSize
        if let sizeOverride, sizeOverride.id == freeText.id {
            size = sizeOverride.size
        } else {
            size = displayedSize ?? boardSize(of: freeText)
        }
        return CGRect(
            x: freeText.position.x,
            y: freeText.position.y,
            width: size.width,
            height: size.height)
    }

    private static func boardSize(of item: BoardItem) -> BoardSize {
        let size = BoardLayout.size(of: item)
        return BoardSize(width: size.width, height: size.height)
    }

    private static func boardSize(of freeText: BoardFreeText) -> BoardSize {
        let size = BoardLayout.size(of: freeText)
        return BoardSize(width: size.width, height: size.height)
    }
}
