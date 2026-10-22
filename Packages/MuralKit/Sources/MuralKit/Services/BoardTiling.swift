import Foundation

/// Mosaico do mural, como num gerenciador de janelas que divide o espaço em árvore (BSP): os
/// cartões soltos ganham blocos sem sobreposição e com vãos iguais.
///
/// Os cartões mantêm o tamanho. Por isso a árvore é equilibrada (divide a lista ao meio, como o
/// `--balance` do yabai) em vez de cada cartão dividir o bloco do anterior: com tamanho fixo, essa
/// divisão sucessiva deixaria o primeiro cartão sozinho num bloco enorme e o resto numa escada.
public enum BoardTiling {
    /// Formato padrão (largura ÷ altura) quando a janela ainda não tem tamanho.
    public static let defaultAspect = 1.6

    /// Posições do mosaico para os cartões, na ordem de leitura atual, a partir de `origin`.
    /// - Parameter aspect: largura ÷ altura desejada para o mosaico todo (a da janela).
    public static func bsp(
        _ items: [BoardItem], aspect: Double, gap: Double = 24, origin: BoardPoint = BoardPoint(x: 80, y: 80)
    ) -> [UUID: BoardPoint] {
        let ordered = readingOrder(items)
        guard !ordered.isEmpty else { return [:] }
        let ratio = aspect.isFinite && aspect > 0 ? aspect : defaultAspect
        // Área-alvo: a soma dos cartões com o vão, no formato pedido. Cada corte é feito no lado
        // mais comprido dela, então o mosaico se aproxima do formato da janela.
        let area = ordered.reduce(0.0) { total, item in
            let size = BoardLayout.cardSize(for: item.kind)
            return total + (size.width + gap) * (size.height + gap)
        }
        let width = (area * ratio).squareRoot()
        let tree = node(for: ordered[...], region: (width, area / width), gap: gap)
        var positions: [UUID: BoardPoint] = [:]
        place(tree, at: origin, gap: gap, into: &positions)
        return positions
    }

    /// De cima para baixo e da esquerda para a direita. Cartões quase na mesma altura (faixas de 80 pt)
    /// contam como a mesma linha; empate fica na ordem da lista.
    static func readingOrder(_ items: [BoardItem]) -> [BoardItem] {
        let band = 80.0
        return items.enumerated()
            .sorted { lhs, rhs in
                let lhsRow = (lhs.element.position.y / band).rounded(.down)
                let rhsRow = (rhs.element.position.y / band).rounded(.down)
                if lhsRow != rhsRow { return lhsRow < rhsRow }
                if lhs.element.position.x != rhs.element.position.x { return lhs.element.position.x < rhs.element.position.x }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private indirect enum Node {
        case leaf(UUID, width: Double, height: Double)
        case split(sideBySide: Bool, Node, Node, width: Double, height: Double)

        var width: Double {
            switch self {
            case .leaf(_, let width, _), .split(_, _, _, let width, _): width
            }
        }

        var height: Double {
            switch self {
            case .leaf(_, _, let height), .split(_, _, _, _, let height): height
            }
        }
    }

    /// Divide a lista ao meio (a primeira metade leva o cartão a mais) no lado mais comprido da região
    /// e mede o bloco de baixo para cima.
    private static func node(for items: ArraySlice<BoardItem>, region: (width: Double, height: Double), gap: Double) -> Node {
        if items.count == 1, let item = items.first {
            let size = BoardLayout.cardSize(for: item.kind)
            return .leaf(item.id, width: size.width, height: size.height)
        }
        let middle = items.startIndex + (items.count + 1) / 2
        let sideBySide = region.width >= region.height
        let half = sideBySide ? (region.width / 2, region.height) : (region.width, region.height / 2)
        let first = node(for: items[..<middle], region: half, gap: gap)
        let second = node(for: items[middle...], region: half, gap: gap)
        let width = sideBySide ? first.width + gap + second.width : max(first.width, second.width)
        let height = sideBySide ? max(first.height, second.height) : first.height + gap + second.height
        return .split(sideBySide: sideBySide, first, second, width: width, height: height)
    }

    /// Posiciona de cima para baixo, alinhando cada bloco no topo e à esquerda do espaço dele.
    private static func place(_ node: Node, at origin: BoardPoint, gap: Double, into positions: inout [UUID: BoardPoint]) {
        switch node {
        case .leaf(let id, _, _):
            positions[id] = BoardLayout.clamped(origin)
        case .split(let sideBySide, let first, let second, _, _):
            place(first, at: origin, gap: gap, into: &positions)
            let next =
                sideBySide
                ? BoardPoint(x: origin.x + first.width + gap, y: origin.y)
                : BoardPoint(x: origin.x, y: origin.y + first.height + gap)
            place(second, at: next, gap: gap, into: &positions)
        }
    }
}

/// Uma organização do mural e o caminho de volta: onde os cartões estavam e onde ela os pôs.
/// Desfazer troca os dois lados, e o refazer é a mesma operação de novo.
public struct BoardArrangement: Equatable, Sendable {
    public var previous: [UUID: BoardPoint]
    public var arranged: [UUID: BoardPoint]

    public init(previous: [UUID: BoardPoint], arranged: [UUID: BoardPoint]) {
        self.previous = previous
        self.arranged = arranged
    }

    /// O caminho inverso: volta para `previous` o que ainda está em `arranged`.
    public var reversed: BoardArrangement {
        BoardArrangement(previous: arranged, arranged: previous)
    }
}
