import Foundation

/// Escolhe onde colocar um cartão novo no mural sem cobrir os existentes.
public enum BoardLayout {
    /// Tamanho padrão de um cartão no mural, por tipo (largura, altura).
    public static func cardSize(for kind: ItemKind) -> (width: Double, height: Double) {
        switch kind {
        case .image, .video: (150, 190)
        case .text, .checklist, .pdf: (120, 150)
        case .sticky: (110, 110)
        case .link: (150, 170)
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
        }
    }

    /// Canto inferior direito ocupado pelos cartões soltos; um mural vazio ocupa zero.
    public static func extent(of items: [BoardItem]) -> (width: Double, height: Double) {
        items.reduce((width: 0, height: 0)) { partial, item in
            let size = cardSize(for: item.kind)
            return (max(partial.width, item.position.x + size.width), max(partial.height, item.position.y + size.height))
        }
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
