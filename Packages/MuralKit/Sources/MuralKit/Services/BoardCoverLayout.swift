import Foundation

/// Enquadramento da capa de um mural: o mural inteiro, reduzido e centralizado na capa.
///
/// Não desenha nada. Diz o que entra na capa e como levar um ponto do mural para ela, para quem desenha e para os
/// testes usarem a mesma conta. Só os cartões soltos e os textos livres contam; o que está dentro de pastas não entra.
public struct BoardCoverLayout: Equatable, Sendable {
    /// Cartões soltos desenhados, na ordem do mural.
    public let items: [BoardItem]
    public let freeTexts: [BoardFreeText]
    /// Pontos da capa por ponto do mural.
    public let scale: Double
    /// Canto superior esquerdo do conteúdo (menor x e menor y entre cartões e textos), em pontos do mural.
    public let contentOrigin: BoardPoint
    /// Onde `contentOrigin` cai na capa; é o que deixa o conteúdo centralizado.
    public let coverOrigin: BoardPoint

    public var isEmpty: Bool { items.isEmpty && freeTexts.isEmpty }

    /// Calcula o enquadramento de `board` numa capa de `coverWidth` × `coverHeight` pontos.
    ///
    /// O retângulo de cada cartão é a posição mais o tamanho de `BoardLayout.cardSize(for:)`; o de cada texto livre,
    /// a posição mais o quadrado de `BoardLayout.freeTextSide`. A escala cabe o conteúdo na capa menos `padding` em
    /// cada lado (no mínimo 1 ponto de área útil) e nunca passa de `maximumScale`, para um mural pequeno não ser
    /// ampliado. Um mural vazio fica com `maximumScale` e as duas origens em zero.
    /// - Parameter maximumItems: com mais cartões soltos que isto, ficam os mais recentes (`createdAt`); em empate vale
    ///   a ordem do mural, e os que ficam mantêm a ordem em que estavam. Os textos livres não têm limite.
    public static func make(
        for board: Board, coverWidth: Double, coverHeight: Double,
        padding: Double = 12, maximumScale: Double = 0.6, maximumItems: Int = 200
    ) -> BoardCoverLayout {
        let items = mostRecent(board.rootItems, limit: maximumItems)
        let freeTexts = board.freeTexts
        guard !items.isEmpty || !freeTexts.isEmpty else {
            return BoardCoverLayout(items: [], freeTexts: [], scale: maximumScale, contentOrigin: .zero, coverOrigin: .zero)
        }

        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        for item in items {
            let size = BoardLayout.cardSize(for: item.kind)
            minX = min(minX, item.position.x)
            minY = min(minY, item.position.y)
            maxX = max(maxX, item.position.x + size.width)
            maxY = max(maxY, item.position.y + size.height)
        }
        for text in freeTexts {
            minX = min(minX, text.position.x)
            minY = min(minY, text.position.y)
            maxX = max(maxX, text.position.x + BoardLayout.freeTextSide)
            maxY = max(maxY, text.position.y + BoardLayout.freeTextSide)
        }

        let contentWidth = maxX - minX
        let contentHeight = maxY - minY
        let usableWidth = max(coverWidth - 2 * padding, 1)
        let usableHeight = max(coverHeight - 2 * padding, 1)
        let scale = min(usableWidth / contentWidth, usableHeight / contentHeight, maximumScale)
        return BoardCoverLayout(
            items: items,
            freeTexts: freeTexts,
            scale: scale,
            contentOrigin: BoardPoint(x: minX, y: minY),
            coverOrigin: BoardPoint(x: (coverWidth - contentWidth * scale) / 2, y: (coverHeight - contentHeight * scale) / 2))
    }

    /// Onde um ponto do mural cai na capa.
    public func coverPoint(for point: BoardPoint) -> BoardPoint {
        BoardPoint(
            x: coverOrigin.x + (point.x - contentOrigin.x) * scale,
            y: coverOrigin.y + (point.y - contentOrigin.y) * scale)
    }

    /// Os `limit` cartões de `createdAt` mais recente, na ordem em que estavam; em empate de data fica o que vem antes.
    private static func mostRecent(_ items: [BoardItem], limit: Int) -> [BoardItem] {
        let limit = max(limit, 0)
        guard items.count > limit else { return items }
        return items.enumerated()
            .sorted { lhs, rhs in
                lhs.element.createdAt == rhs.element.createdAt ? lhs.offset < rhs.offset : lhs.element.createdAt > rhs.element.createdAt
            }
            .prefix(limit)
            .sorted { $0.offset < $1.offset }
            .map(\.element)
    }
}
