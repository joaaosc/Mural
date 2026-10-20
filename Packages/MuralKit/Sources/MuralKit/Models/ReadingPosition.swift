import Foundation

/// Posição persistida de leitura. IDs de conteúdo são UUIDs de `BoardItem`;
/// `BoardID` fica reservado para a identidade do mural.
public enum ReadingPosition: Codable, Equatable, Sendable {
    case collection(
        folderID: UUID,
        firstVisibleItemID: UUID?,
        relativeOffset: Double,
        fallbackContentY: Double
    )
    case item(itemID: UUID, visibleContentY: Double)
    case pdf(itemID: UUID, pageIndex: Int, scale: Double, pointInPage: BoardPoint)

    public var targetItemID: UUID {
        switch self {
        case .collection(let folderID, _, _, _): folderID
        case .item(let itemID, _), .pdf(let itemID, _, _, _): itemID
        }
    }

    /// Captura a âncora mais estável disponível numa coleção. `visibleRect` e os
    /// frames estão no mesmo espaço de conteúdo do `ScrollGeometry`.
    public static func collectionSnapshot(
        folderID: UUID,
        visibleRect: CGRect,
        itemFrames: [(id: UUID, frame: CGRect)]
    ) -> ReadingPosition {
        let first = itemFrames.first {
            $0.frame.maxY > visibleRect.minY && $0.frame.minY < visibleRect.maxY
        }
        let relativeOffset = first.map { max(0, visibleRect.minY - $0.frame.minY) } ?? 0
        return .collection(
            folderID: folderID,
            firstVisibleItemID: first?.id,
            relativeOffset: relativeOffset,
            fallbackContentY: max(0, visibleRect.minY))
    }

    /// Calcula o Y de restauração da coleção. O item é preferido; se ele não
    /// existir mais, o fallback é usado e limitado ao intervalo alcançável.
    public static func collectionTargetY(
        _ position: ReadingPosition,
        itemFrame: CGRect?,
        contentHeight: CGFloat,
        viewportHeight: CGFloat,
        contentInsetsTop: CGFloat = 0,
        contentInsetsBottom: CGFloat = 0
    ) -> CGFloat? {
        guard case .collection(_, _, let relativeOffset, let fallbackContentY) = position else { return nil }
        let proposed = itemFrame.map { $0.minY + relativeOffset } ?? fallbackContentY
        let minimum = -contentInsetsTop
        let maximum = max(minimum, contentHeight - viewportHeight + contentInsetsBottom)
        return min(max(minimum, proposed), maximum)
    }

    /// Limita uma posição vertical de conteúdo aos limites reais de um
    /// `ScrollGeometry`, incluindo insets assimétricos.
    public static func itemTargetY(
        _ position: ReadingPosition,
        contentHeight: CGFloat,
        viewportHeight: CGFloat,
        contentInsetsTop: CGFloat = 0,
        contentInsetsBottom: CGFloat = 0
    ) -> CGFloat? {
        guard case .item(_, let visibleContentY) = position else { return nil }
        let minimum = -contentInsetsTop
        let maximum = max(minimum, contentHeight - viewportHeight + contentInsetsBottom)
        return min(max(minimum, visibleContentY), maximum)
    }

    /// Faz o clamp defensivo dos valores recebidos do PDFKit antes da criação
    /// de um snapshot persistível.
    public static func clampedPDF(
        itemID: UUID,
        pageIndex: Int,
        pageCount: Int,
        scale: Double,
        scaleRange: ClosedRange<Double>,
        pointInPage: BoardPoint,
        pageBounds: CGRect
    ) -> ReadingPosition {
        let maxPage = max(0, pageCount - 1)
        let page = min(max(0, pageIndex), maxPage)
        let boundedScale = min(max(scale.isFinite ? scale : scaleRange.lowerBound, scaleRange.lowerBound), scaleRange.upperBound)
        let point = BoardPoint(
            x: min(max(pointInPage.x, pageBounds.minX), pageBounds.maxX),
            y: min(max(pointInPage.y, pageBounds.minY), pageBounds.maxY))
        return .pdf(itemID: itemID, pageIndex: page, scale: boundedScale, pointInPage: point)
    }
}
