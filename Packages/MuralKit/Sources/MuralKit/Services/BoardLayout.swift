import Foundation

/// Escolhe onde colocar um cartão novo no mural sem cobrir os existentes.
public enum BoardLayout {
    /// Tamanho padrão de um cartão no mural, por tipo (largura, altura).
    public static func cardSize(for kind: ItemKind) -> (width: Double, height: Double) {
        switch kind {
        case .image, .video: (150, 190)
        case .text, .checklist, .pdf: (120, 150)
        case .sticky: (110, 110)
        case .folder: (120, 160)
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

    static func overlaps(
        _ a: BoardPoint, _ sa: (width: Double, height: Double),
        _ b: BoardPoint, _ sb: (width: Double, height: Double), gap: Double
    ) -> Bool {
        a.x < b.x + sb.width + gap && b.x < a.x + sa.width + gap && a.y < b.y + sb.height + gap && b.y < a.y + sa.height + gap
    }
}
