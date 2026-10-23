import Foundation

/// Escolhe onde colocar um cartão novo no mural sem cobrir os existentes.
public enum BoardLayout {
    /// Lado fixo de um texto livre no mural. Textos livres nunca herdam a proporção de cartões.
    public static let freeTextSide: Double = 180

    public static var freeTextSize: (width: Double, height: Double) {
        (width: freeTextSide, height: freeTextSide)
    }

    /// Tamanho padrão de um cartão no mural, por tipo (largura, altura).
    public static func cardSize(for kind: ItemKind) -> (width: Double, height: Double) {
        switch kind {
        case .image, .video: (150, 190)
        case .text, .checklist, .pdf: (120, 150)
        case .sticky: (110, 110)
        case .link: (150, 170)
        case .reminder: (160, 96)
        case .folder: (120, 160)
        }
    }

    /// Proporção largura ÷ altura de um cartão na grade da pasta; fotos usam a do arquivo.
    public static func aspectRatio(for item: BoardItem) -> Double {
        if item.kind == .image, let meta = item.imageMetadata, meta.pixelHeight > 0 {
            return Double(meta.pixelWidth) / Double(meta.pixelHeight)
        }
        return switch item.kind {
        case .image: 0.75
        case .video: 0.8
        case .pdf: 0.77
        case .text, .checklist, .folder: 0.72
        case .sticky: 1.25
        case .link: 0.85
        case .reminder: 1.6
        }
    }

    /// Canto inferior direito ocupado pelos cartões soltos; um mural vazio ocupa zero.
    public static func extent(of items: [BoardItem]) -> (width: Double, height: Double) {
        items.reduce((width: 0, height: 0)) { partial, item in
            let size = cardSize(for: item.kind)
            return (max(partial.width, item.position.x + size.width), max(partial.height, item.position.y + size.height))
        }
    }

    /// Extensão ocupada pelos cartões e textos livres do mural.
    public static func extent(
        of items: [BoardItem], freeTexts: [BoardFreeText]
    ) -> (width: Double, height: Double) {
        let itemsExtent = extent(of: items)
        return freeTexts.reduce(itemsExtent) { partial, text in
            (
                width: max(partial.width, text.position.x + freeTextSide),
                height: max(partial.height, text.position.y + freeTextSide)
            )
        }
    }

    /// Retângulo ocupado por um texto livre, sempre quadrado.
    public static func freeTextRect(for text: BoardFreeText) -> (minX: Double, minY: Double, width: Double, height: Double) {
        (text.position.x, text.position.y, freeTextSide, freeTextSide)
    }

    public static func freeTextBounds(of texts: [BoardFreeText]) -> (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        guard let first = texts.first else { return nil }
        var minX = first.position.x
        var minY = first.position.y
        var maxX = first.position.x + freeTextSide
        var maxY = first.position.y + freeTextSide
        for text in texts.dropFirst() {
            minX = min(minX, text.position.x)
            minY = min(minY, text.position.y)
            maxX = max(maxX, text.position.x + freeTextSide)
            maxY = max(maxY, text.position.y + freeTextSide)
        }
        return (minX, minY, maxX, maxY)
    }

    public static func freeTextCenter(of texts: [BoardFreeText]) -> BoardPoint {
        guard let bounds = freeTextBounds(of: texts) else { return .zero }
        return BoardPoint(x: (bounds.minX + bounds.maxX) / 2, y: (bounds.minY + bounds.maxY) / 2)
    }

    /// Primeira posição de uma grade que não encosta em cartões nem em outros textos livres.
    public static func freeTextPosition(
        avoiding items: [BoardItem], freeTexts: [BoardFreeText],
        origin: BoardPoint = BoardPoint(x: 80, y: 80), step: Double = 40,
        columns: Int = 24, gap: Double = 24
    ) -> BoardPoint {
        let occupied =
            items.map { ($0.position, cardSize(for: $0.kind)) }
            + freeTexts.map {
                ($0.position, freeTextSize)
            }
        var row = 0
        while row < 200 {
            for column in 0..<columns {
                let candidate = BoardPoint(x: origin.x + Double(column) * step, y: origin.y + Double(row) * step)
                let clear = occupied.allSatisfy { other in
                    !overlaps(candidate, freeTextSize, other.0, other.1, gap: gap)
                }
                if clear { return candidate }
            }
            row += 1
        }
        return BoardPoint(x: origin.x, y: origin.y + Double(items.count + freeTexts.count) * step)
    }

    /// Texto livre sob um ponto; em sobreposição, vale o último da lista.
    public static func freeTextID(
        at point: BoardPoint, among texts: [BoardFreeText], excluding excluded: UUID? = nil
    ) -> UUID? {
        texts.last { text in
            guard text.id != excluded else { return false }
            return point.x >= text.position.x && point.x < text.position.x + freeTextSide
                && point.y >= text.position.y && point.y < text.position.y + freeTextSide
        }?.id
    }

    /// Percorre uma grade (passo fixo) e devolve a primeira célula que não encosta em ninguém.
    public static func freePosition(
        for kind: ItemKind,
        avoiding items: [BoardItem],
        origin: BoardPoint = BoardPoint(x: 80, y: 80),
        step: Double = 40,
        columns: Int = 24,
        gap: Double = 24
    ) -> BoardPoint {
        let size = cardSize(for: kind)
        let occupied = items.map { item -> (BoardPoint, (width: Double, height: Double)) in
            (item.position, cardSize(for: item.kind))
        }
        var row = 0
        while row < 200 {
            for column in 0..<columns {
                let candidate = BoardPoint(x: origin.x + Double(column) * step, y: origin.y + Double(row) * step)
                let clear = occupied.allSatisfy { other in
                    !overlaps(candidate, size, other.0, other.1, gap: gap)
                }
                if clear { return candidate }
            }
            row += 1
        }
        return BoardPoint(x: origin.x, y: origin.y + Double(items.count) * step)
    }

    /// Arredonda a posição e a mantém dentro do mural, que começa em (0, 0).
    public static func clamped(_ point: BoardPoint) -> BoardPoint {
        let x = point.x.rounded()
        let y = point.y.rounded()
        // `> 0` no lugar de `max` também troca -0 e valores inválidos (NaN) por 0.
        return BoardPoint(x: x > 0 ? x : 0, y: y > 0 ? y : 0)
    }

    /// Pasta solta sob o ponto, para receber um cartão solto nela. Com pastas sobrepostas vale a de cima (a última da lista).
    /// As bordas esquerda e superior contam como dentro; a direita e a inferior, não.
    /// - Parameter excluded: pasta a ignorar, como a que está sendo arrastada.
    public static func folderID(at point: BoardPoint, among items: [BoardItem], excluding excluded: UUID? = nil) -> UUID? {
        let size = cardSize(for: .folder)
        let hit = items.last { item in
            guard item.kind == .folder, item.parentID == nil, item.id != excluded else { return false }
            return point.x >= item.position.x && point.x < item.position.x + size.width
                && point.y >= item.position.y && point.y < item.position.y + size.height
        }
        return hit?.id
    }

    static func overlaps(
        _ a: BoardPoint, _ sa: (width: Double, height: Double),
        _ b: BoardPoint, _ sb: (width: Double, height: Double), gap: Double
    ) -> Bool {
        a.x < b.x + sb.width + gap && b.x < a.x + sa.width + gap && a.y < b.y + sb.height + gap && b.y < a.y + sa.height + gap
    }
}
