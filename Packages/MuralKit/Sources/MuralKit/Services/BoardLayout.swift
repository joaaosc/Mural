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
        case .music: (150, 210)
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
        case .music: 0.71
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

    /// Retângulo delimitador ocupado pelos cartões soltos; um mural vazio devolve nulo.
    public static func bounds(of items: [BoardItem]) -> (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        guard let first = items.first else { return nil }
        let firstSize = cardSize(for: first.kind)
        var minX = first.position.x
        var minY = first.position.y
        var maxX = first.position.x + firstSize.width
        var maxY = first.position.y + firstSize.height
        for item in items.dropFirst() {
            let size = cardSize(for: item.kind)
            minX = min(minX, item.position.x)
            minY = min(minY, item.position.y)
            maxX = max(maxX, item.position.x + size.width)
            maxY = max(maxY, item.position.y + size.height)
        }
        return (minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    /// Centro da área ocupada pelos cartões soltos; um mural vazio devolve (0, 0).
    public static func center(of items: [BoardItem]) -> BoardPoint {
        guard let b = bounds(of: items) else { return .zero }
        return BoardPoint(x: (b.minX + b.maxX) / 2, y: (b.minY + b.maxY) / 2)
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
        return freePosition(
            size: size, avoiding: occupied, origin: origin, step: step, columns: columns, gap: gap)
    }

    /// Variante usada por lotes, que preserva o tamanho real de cada cartão já ocupado.
    private static func freePosition(
        size: (width: Double, height: Double),
        avoiding occupied: [(BoardPoint, (width: Double, height: Double))],
        origin: BoardPoint,
        step: Double = 40,
        columns: Int = 24,
        gap: Double = 24
    ) -> BoardPoint {
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
        return BoardPoint(x: origin.x, y: origin.y + Double(occupied.count) * step)
    }

    /// Distribui um lote perto da âncora indicada, usando o centro da janela ou
    /// o ponto real de drop como referência. A posição guardada é o canto do
    /// cartão; por isso a primeira vaga é centralizada no ponto recebido.
    public static func importPositions(
        kinds: [ItemKind], anchor: BoardPoint?, avoiding items: [BoardItem], gap: Double = 24
    ) -> [BoardPoint] {
        guard let anchor else {
            var occupied = items
            return kinds.map { kind in
                let position = freePosition(for: kind, avoiding: occupied, gap: gap)
                occupied.append(BoardItem(kind: kind, title: "", position: position))
                return position
            }
        }
        var occupied = items.map { ($0.position, cardSize(for: $0.kind)) }
        var result: [BoardPoint] = []
        for (index, kind) in kinds.enumerated() {
            let size = cardSize(for: kind)
            let candidates = importCandidates(anchor: anchor, size: size, index: index)
            let position =
                candidates.first { candidate in
                    occupied.allSatisfy { other in !overlaps(candidate, size, other.0, other.1, gap: gap) }
                }
                ?? freePosition(
                    size: size,
                    avoiding: occupied,
                    origin: anchor)
            result.append(position)
            occupied.append((position, size))
        }
        return result
    }

    private static func importCandidates(anchor: BoardPoint, size: (width: Double, height: Double), index: Int) -> [BoardPoint] {
        let center = BoardPoint(x: anchor.x - size.width / 2, y: anchor.y - size.height / 2)
        guard index > 0 else { return [clamped(center)] }
        let ring = Double((index + 1) / 2) * 1.25
        let angle = Double(index) * (.pi / 3)
        return [
            clamped(BoardPoint(x: center.x + cos(angle) * size.width * ring, y: center.y + sin(angle) * size.height * ring)),
            clamped(BoardPoint(x: center.x + size.width * Double(index), y: center.y)),
            clamped(BoardPoint(x: center.x, y: center.y + size.height * Double(index))),
        ]
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
