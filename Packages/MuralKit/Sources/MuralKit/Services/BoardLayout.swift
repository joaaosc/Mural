import Foundation

/// Escolhe onde colocar um cartão novo no mural sem cobrir os existentes.
public enum BoardLayout {
    /// Lado do quadrado padrão de um texto livre no mural, usado enquanto a pessoa não escolhe outro tamanho
    /// (`BoardFreeText.size`). Textos livres nunca herdam a proporção de cartões.
    public static let freeTextSide: Double = 180

    /// Tamanho padrão de um texto livre. O de um texto que já existe vem de `size(of:)`.
    public static var freeTextSize: (width: Double, height: Double) {
        (width: freeTextSide, height: freeTextSide)
    }

    /// Tamanho padrão de um cartão no mural, por tipo (largura, altura). O de um cartão que já existe vem de `size(of:)`,
    /// que leva em conta o tamanho escolhido pela pessoa.
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

    // MARK: Tamanho escolhido pela pessoa

    /// Menor tamanho de um post-it solto no mural (60 × 60 pontos): abaixo disso o texto deixa de ser legível e o canto de
    /// redimensionar passaria a cobrir o cartão inteiro.
    public static let minimumStickySize = BoardSize(width: 60, height: 60)

    /// Maior tamanho de um post-it solto no mural (480 × 480 pontos): acima disso um único post-it passaria a ocupar boa parte
    /// da janela e esconderia os vizinhos.
    public static let maximumStickySize = BoardSize(width: 480, height: 480)

    /// Menor tamanho de um texto livre no mural (100 × 60 pontos). É mais largo que alto porque o texto corre em linhas.
    public static let minimumFreeTextSize = BoardSize(width: 100, height: 60)

    /// Maior tamanho de um texto livre no mural (720 × 540 pontos): acima disso uma única anotação passaria a ocupar a janela
    /// inteira. O limite de caracteres (`BoardFreeText.maximumCharacters`) não muda com o tamanho.
    public static let maximumFreeTextSize = BoardSize(width: 720, height: 540)

    /// Lados dos tamanhos quadrados oferecidos para um post-it, do menor ao maior. O segundo é o padrão (110).
    /// Os nomes mostrados na tela ficam no app.
    public static let stickyPresetSides: [Double] = [80, 110, 160, 220]

    /// Lados dos tamanhos quadrados oferecidos para um texto livre, do menor ao maior. O segundo é o padrão (180).
    /// Os nomes mostrados na tela ficam no app.
    public static let freeTextPresetSides: [Double] = [120, 180, 260, 360]

    /// Se a pessoa pode mudar o tamanho de um cartão solto deste tipo. Por ora, só o post-it.
    public static func isResizable(_ kind: ItemKind) -> Bool {
        limits(for: kind) != nil
    }

    /// Tamanho de um cartão no mural: o escolhido pela pessoa, se o tipo muda de tamanho, ou o padrão do tipo.
    /// Todas as contas de espaço (área ocupada, vagas livres, acerto do clique, mosaico, capa) partem daqui.
    ///
    /// O tamanho guardado passa pelos mesmos limites da normalização. Isso só importa para um mural editado por fora ou vindo de
    /// uma versão com outros limites: um cartão sem largura ou sem altura ficaria invisível e impossível de pegar de novo.
    public static func size(of item: BoardItem) -> (width: Double, height: Double) {
        guard let limits = limits(for: item.kind), let stored = item.size else { return cardSize(for: item.kind) }
        let shown = limited(stored, minimum: limits.minimum, maximum: limits.maximum)
        return (width: shown.width, height: shown.height)
    }

    /// Tamanho de um texto livre no mural: o escolhido pela pessoa ou o quadrado padrão. Vale a mesma proteção de
    /// `size(of:)` contra um tamanho guardado fora dos limites.
    public static func size(of freeText: BoardFreeText) -> (width: Double, height: Double) {
        guard let stored = freeText.size else { return freeTextSize }
        let shown = limited(stored, minimum: minimumFreeTextSize, maximum: maximumFreeTextSize)
        return (width: shown.width, height: shown.height)
    }

    /// O tamanho de um cartão como ele é guardado: arredondado para pontos inteiros e preso aos limites do tipo (um valor
    /// inválido, NaN ou infinito, vira o mínimo). `nil` quando o tamanho é o padrão do tipo, para o mural não passar a exigir
    /// um formato novo (`Board.currentFormatVersion`) sem que ninguém tenha escolhido nada, ou quando o tipo não muda de tamanho.
    public static func normalizedSize(_ size: BoardSize?, for kind: ItemKind) -> BoardSize? {
        guard let limits = limits(for: kind), let size else { return nil }
        let result = limited(size, minimum: limits.minimum, maximum: limits.maximum)
        let standard = cardSize(for: kind)
        return result.width == standard.width && result.height == standard.height ? nil : result
    }

    /// O mesmo de `normalizedSize(_:for:)` para um texto livre, cujo padrão é o quadrado de `freeTextSide`.
    public static func normalizedFreeTextSize(_ size: BoardSize?) -> BoardSize? {
        guard let size else { return nil }
        let result = limited(size, minimum: minimumFreeTextSize, maximum: maximumFreeTextSize)
        return result.width == freeTextSide && result.height == freeTextSide ? nil : result
    }

    /// Tamanho de um post-it depois de a pessoa arrastar o canto inferior direito dele: o canto de cima, à esquerda, fica parado, e
    /// o tamanho atual (`size(of:)`) cresce ou encolhe o que o ponteiro andou. O resultado já respeita os limites e os pontos
    /// inteiros, e serve tanto para o desenho durante o arrasto quanto para o valor gravado ao soltar. Um cartão que não muda de
    /// tamanho continua com o tamanho atual.
    /// - Parameters:
    ///   - deltaWidth: quanto o ponteiro andou na horizontal, em pontos do mural (para a direita é positivo).
    ///   - deltaHeight: quanto o ponteiro andou na vertical (para baixo é positivo).
    ///   - keepingProportion: mantém a proporção do tamanho atual. O lado que mais andou, em proporção, manda e o outro o acompanha;
    ///     se um limite barra um dos lados, os dois param juntos, e a proporção não se perde.
    public static func resizedSize(
        of item: BoardItem, deltaWidth: Double, deltaHeight: Double, keepingProportion: Bool = false
    ) -> BoardSize {
        let current = size(of: item)
        guard let limits = limits(for: item.kind) else { return BoardSize(width: current.width, height: current.height) }
        return resized(
            from: BoardSize(width: current.width, height: current.height), deltaWidth: deltaWidth, deltaHeight: deltaHeight,
            keepingProportion: keepingProportion, minimum: limits.minimum, maximum: limits.maximum)
    }

    /// O mesmo de `resizedSize(of:deltaWidth:deltaHeight:keepingProportion:)` para um texto livre.
    public static func resizedSize(
        of freeText: BoardFreeText, deltaWidth: Double, deltaHeight: Double, keepingProportion: Bool = false
    ) -> BoardSize {
        let current = size(of: freeText)
        return resized(
            from: BoardSize(width: current.width, height: current.height), deltaWidth: deltaWidth, deltaHeight: deltaHeight,
            keepingProportion: keepingProportion, minimum: minimumFreeTextSize, maximum: maximumFreeTextSize)
    }

    /// Quanto o conteúdo de um cartão cresce junto com ele: a raiz quadrada da razão entre a área atual e a padrão. Um post-it de
    /// 220 × 220 (quatro vezes a área de 110 × 110) dá 2, e um de 110 × 220 dá cerca de 1,41. A raiz mantém o texto proporcional
    /// ao papel quando só um dos lados muda, e o resultado fica entre 0,5 e 4 para a letra nunca sumir nem tomar o cartão todo.
    /// Medidas inválidas (zero, negativas, NaN) dão 1, que deixa o conteúdo como está.
    public static func contentScale(width: Double, height: Double, defaultWidth: Double, defaultHeight: Double) -> Double {
        guard width.isFinite, height.isFinite, defaultWidth.isFinite, defaultHeight.isFinite,
            width > 0, height > 0, defaultWidth > 0, defaultHeight > 0
        else { return 1 }
        let ratio = (width * height) / (defaultWidth * defaultHeight)
        return min(max(ratio.squareRoot(), 0.5), 4)
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
        var extent = (width: 0.0, height: 0.0)
        for item in items {
            let itemSize = size(of: item)
            extent.width = max(extent.width, item.position.x + itemSize.width)
            extent.height = max(extent.height, item.position.y + itemSize.height)
        }
        return extent
    }

    /// Extensão ocupada pelos cartões e textos livres do mural.
    public static func extent(
        of items: [BoardItem], freeTexts: [BoardFreeText]
    ) -> (width: Double, height: Double) {
        let itemsExtent = extent(of: items)
        var extent = itemsExtent
        for text in freeTexts {
            let textSize = size(of: text)
            extent.width = max(extent.width, text.position.x + textSize.width)
            extent.height = max(extent.height, text.position.y + textSize.height)
        }
        return extent
    }

    /// Primeira posição de uma grade que não encosta em cartões nem em outros textos livres. O texto novo tem o tamanho padrão;
    /// quem já está no mural ocupa o tamanho que tem.
    public static func freeTextPosition(
        avoiding items: [BoardItem], freeTexts: [BoardFreeText],
        origin: BoardPoint = BoardPoint(x: 80, y: 80), step: Double = 40,
        columns: Int = 24, gap: Double = 24
    ) -> BoardPoint {
        var occupied: [(BoardPoint, (width: Double, height: Double))] = []
        occupied.reserveCapacity(items.count + freeTexts.count)
        for item in items {
            occupied.append((item.position, size(of: item)))
        }
        for freeText in freeTexts {
            occupied.append((freeText.position, size(of: freeText)))
        }
        var row = 0
        while row < 200 {
            for column in 0..<columns {
                let candidate = BoardPoint(x: origin.x + Double(column) * step, y: origin.y + Double(row) * step)
                var clear = true
                for other in occupied {
                    if overlaps(candidate, freeTextSize, other.0, other.1, gap: gap) {
                        clear = false
                        break
                    }
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
        for text in texts.reversed() {
            guard text.id != excluded else { continue }
            let textSize = size(of: text)
            if point.x >= text.position.x && point.x < text.position.x + textSize.width
                && point.y >= text.position.y && point.y < text.position.y + textSize.height
            {
                return text.id
            }
        }
        return nil
    }

    /// Retângulo delimitador ocupado pelos cartões soltos; um mural vazio devolve nulo.
    public static func bounds(of items: [BoardItem]) -> (minX: Double, minY: Double, maxX: Double, maxY: Double)? {
        guard let first = items.first else { return nil }
        let firstSize = size(of: first)
        var minX = first.position.x
        var minY = first.position.y
        var maxX = first.position.x + firstSize.width
        var maxY = first.position.y + firstSize.height
        for item in items.dropFirst() {
            let itemSize = size(of: item)
            minX = min(minX, item.position.x)
            minY = min(minY, item.position.y)
            maxX = max(maxX, item.position.x + itemSize.width)
            maxY = max(maxY, item.position.y + itemSize.height)
        }
        return (minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    /// Centro da área ocupada pelos cartões soltos; um mural vazio devolve (0, 0).
    public static func center(of items: [BoardItem]) -> BoardPoint {
        guard let b = bounds(of: items) else { return .zero }
        return BoardPoint(x: (b.minX + b.maxX) / 2, y: (b.minY + b.maxY) / 2)
    }

    /// Percorre uma grade (passo fixo) e devolve a primeira célula que não encosta em ninguém. O cartão novo tem o tamanho
    /// padrão do tipo; os que já estão no mural ocupam o tamanho que têm.
    public static func freePosition(
        for kind: ItemKind,
        avoiding items: [BoardItem],
        origin: BoardPoint = BoardPoint(x: 80, y: 80),
        step: Double = 40,
        columns: Int = 24,
        gap: Double = 24
    ) -> BoardPoint {
        let newSize = cardSize(for: kind)
        var occupied: [(BoardPoint, (width: Double, height: Double))] = []
        occupied.reserveCapacity(items.count)
        for item in items {
            occupied.append((item.position, size(of: item)))
        }
        return freePosition(
            size: newSize, avoiding: occupied, origin: origin, step: step, columns: columns, gap: gap)
    }

    /// O mesmo de `freePosition(for:avoiding:)` para um cartão que já existe e volta ao mural (saindo de uma pasta): a vaga é
    /// procurada com o tamanho que ele tem (`size(of:)`), para um post-it redimensionado não cair por cima dos vizinhos.
    public static func freePosition(for item: BoardItem, avoiding items: [BoardItem]) -> BoardPoint {
        var occupied: [(BoardPoint, (width: Double, height: Double))] = []
        occupied.reserveCapacity(items.count)
        for other in items {
            occupied.append((other.position, size(of: other)))
        }
        return freePosition(size: size(of: item), avoiding: occupied, origin: BoardPoint(x: 80, y: 80))
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
                var clear = true
                for other in occupied {
                    if overlaps(candidate, size, other.0, other.1, gap: gap) {
                        clear = false
                        break
                    }
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
    /// Os cartões do lote têm o tamanho padrão do tipo; os que já estão no mural ocupam o tamanho que têm.
    public static func importPositions(
        kinds: [ItemKind], anchor: BoardPoint?, avoiding items: [BoardItem], gap: Double = 24
    ) -> [BoardPoint] {
        guard let anchor else {
            var occupied: [(BoardPoint, (width: Double, height: Double))] = []
            occupied.reserveCapacity(items.count + kinds.count)
            for item in items {
                occupied.append((item.position, size(of: item)))
            }
            var result: [BoardPoint] = []
            result.reserveCapacity(kinds.count)
            for kind in kinds {
                let newSize = cardSize(for: kind)
                let position = freePosition(size: newSize, avoiding: occupied, origin: BoardPoint(x: 80, y: 80), gap: gap)
                result.append(position)
                occupied.append((position, newSize))
            }
            return result
        }
        var occupied: [(BoardPoint, (width: Double, height: Double))] = []
        occupied.reserveCapacity(items.count + kinds.count)
        for item in items {
            occupied.append((item.position, size(of: item)))
        }
        var result: [BoardPoint] = []
        for (index, kind) in kinds.enumerated() {
            let newSize = cardSize(for: kind)
            let candidates = importCandidates(anchor: anchor, size: newSize, index: index)
            var position: BoardPoint?
            for candidate in candidates {
                var clear = true
                for other in occupied {
                    if overlaps(candidate, newSize, other.0, other.1, gap: gap) {
                        clear = false
                        break
                    }
                }
                if clear {
                    position = candidate
                    break
                }
            }
            let resolvedPosition = position ?? freePosition(size: newSize, avoiding: occupied, origin: anchor)
            result.append(resolvedPosition)
            occupied.append((resolvedPosition, newSize))
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
    /// Pastas não mudam de tamanho: o tamanho é sempre o padrão do tipo.
    /// - Parameter excluded: pasta a ignorar, como a que está sendo arrastada.
    public static func folderID(at point: BoardPoint, among items: [BoardItem], excluding excluded: UUID? = nil) -> UUID? {
        let size = cardSize(for: .folder)
        for item in items.reversed() {
            guard item.kind == .folder, item.parentID == nil, item.id != excluded else { continue }
            if point.x >= item.position.x && point.x < item.position.x + size.width
                && point.y >= item.position.y && point.y < item.position.y + size.height
            {
                return item.id
            }
        }
        return nil
    }

    static func overlaps(
        _ a: BoardPoint, _ sa: (width: Double, height: Double),
        _ b: BoardPoint, _ sb: (width: Double, height: Double), gap: Double
    ) -> Bool {
        a.x < b.x + sb.width + gap && b.x < a.x + sa.width + gap && a.y < b.y + sb.height + gap && b.y < a.y + sa.height + gap
    }

    // MARK: Interno

    /// Menor e maior tamanho de um tipo que muda de tamanho; `nil` para os que não mudam.
    private static func limits(for kind: ItemKind) -> (minimum: BoardSize, maximum: BoardSize)? {
        switch kind {
        case .sticky: (minimumStickySize, maximumStickySize)
        default: nil
        }
    }

    /// Arredonda o tamanho para pontos inteiros e o prende entre o mínimo e o máximo; NaN e infinito viram o mínimo.
    private static func limited(_ size: BoardSize, minimum: BoardSize, maximum: BoardSize) -> BoardSize {
        BoardSize(
            width: limited(size.width, minimum: minimum.width, maximum: maximum.width),
            height: limited(size.height, minimum: minimum.height, maximum: maximum.height))
    }

    private static func limited(_ value: Double, minimum: Double, maximum: Double) -> Double {
        guard value.isFinite else { return minimum }
        return min(max(value.rounded(), minimum), maximum)
    }

    /// A conta de `resizedSize(of:deltaWidth:deltaHeight:keepingProportion:)`, igual para qualquer tipo de elemento.
    private static func resized(
        from start: BoardSize, deltaWidth: Double, deltaHeight: Double, keepingProportion: Bool,
        minimum: BoardSize, maximum: BoardSize
    ) -> BoardSize {
        guard deltaWidth.isFinite, deltaHeight.isFinite, start.width > 0, start.height > 0 else { return start }
        let wantedWidth = start.width + deltaWidth
        let wantedHeight = start.height + deltaHeight
        guard keepingProportion else {
            return limited(BoardSize(width: wantedWidth, height: wantedHeight), minimum: minimum, maximum: maximum)
        }
        // O lado que mais andou, em proporção do tamanho de partida, decide quanto o todo cresce; o outro o acompanha.
        let widthFactor = wantedWidth / start.width
        let heightFactor = wantedHeight / start.height
        let wanted = abs(widthFactor - 1) >= abs(heightFactor - 1) ? widthFactor : heightFactor
        // O fator também respeita os limites dos dois lados juntos: prender só um deles desmancharia a proporção.
        let lowest = max(minimum.width / start.width, minimum.height / start.height)
        let highest = min(maximum.width / start.width, maximum.height / start.height)
        let factor = lowest <= highest ? min(max(wanted, lowest), highest) : 1
        return limited(BoardSize(width: start.width * factor, height: start.height * factor), minimum: minimum, maximum: maximum)
    }
}
