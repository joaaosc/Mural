import Foundation

/// Mosaico do mural, como num gerenciador de janelas que divide o espaço em árvore (BSP): os
/// cartões soltos ganham blocos sem sobreposição e com vãos iguais.
///
/// Os cartões mantêm o tamanho, o padrão do tipo ou o que a pessoa escolheu (`BoardLayout.size(of:)`). Por isso a árvore é
/// equilibrada (divide a lista ao meio, como o `--balance` do yabai) em vez de cada cartão dividir o bloco do anterior: com
/// tamanho fixo, essa divisão sucessiva deixaria o primeiro cartão sozinho num bloco enorme e o resto numa escada.
public enum BoardTiling {
    /// Formato padrão (largura ÷ altura) quando a janela ainda não tem tamanho.
    public static let defaultAspect = 1.6

    /// Posições do mosaico para os cartões, na ordem em que foram criados, a partir de `origin`.
    /// - Parameter aspect: largura ÷ altura desejada para o mosaico todo (a da janela).
    public static func bsp(
        _ items: [BoardItem], aspect: Double, gap: Double = 24, origin: BoardPoint = BoardPoint(x: 80, y: 80)
    ) -> [UUID: BoardPoint] {
        let ordered = insertionOrder(items)
        guard !ordered.isEmpty else { return [:] }
        let sized = ordered.map {
            let size = BoardLayout.size(of: $0)
            return SizedItem(item: $0, size: BoardSize(width: size.width, height: size.height))
        }
        let ratio = aspect.isFinite && aspect > 0 ? aspect : defaultAspect
        // Área-alvo: a soma dos cartões com o vão, no formato pedido. Cada corte é feito no lado
        // mais comprido dela, então o mosaico se aproxima do formato da janela.
        let area = sized.reduce(0.0) { total, entry in
            return total + (entry.size.width + gap) * (entry.size.height + gap)
        }
        let width = (area * ratio).squareRoot()
        let tree = node(for: sized[...], region: (width, area / width), gap: gap)
        var positions: [UUID: BoardPoint] = [:]
        place(tree, at: origin, gap: gap, into: &positions)
        return positions
    }

    /// Do mais antigo para o mais novo, como as janelas que um WM vai encaixando; empate fica na ordem
    /// da lista. Não depende da posição: organizar de novo não embaralha o mosaico (a ordem de leitura
    /// de um mosaico intercala os blocos da árvore e mudaria a cada vez).
    static func insertionOrder(_ items: [BoardItem]) -> [BoardItem] {
        items.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.createdAt != rhs.element.createdAt { return lhs.element.createdAt < rhs.element.createdAt }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private struct SizedItem {
        let item: BoardItem
        let size: BoardSize
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
    private static func node(for items: ArraySlice<SizedItem>, region: (width: Double, height: Double), gap: Double) -> Node {
        if items.count == 1, let entry = items.first {
            return .leaf(entry.item.id, width: entry.size.width, height: entry.size.height)
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
