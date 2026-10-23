import CoreGraphics

/// Geometria do post-it solto dentro da pasta, separada da view para poder ser testada.
///
/// O lugar guardado (`BoardItem.folderPosition`) é o canto superior esquerdo do post-it: `x` a partir do meio da área dos
/// cartões e `y` a partir do topo. Como as colunas ficam centralizadas, o post-it acompanha as colunas quando a janela muda
/// de largura; numa janela estreita, ele encosta na borda sem perder o lugar guardado.
nonisolated enum StickyPlacement {
    /// 180 × 144: a coluna de notas mais larga (300 × 0,6) com a proporção do post-it na pasta (1,25).
    static let size = CGSize(width: 180, height: 144)

    /// Quadro do post-it numa área de largura `width`, a partir do lugar guardado: dentro da área na horizontal, nunca acima do topo.
    static func frame(for position: CGPoint, width: CGFloat) -> CGRect {
        let x = min(max(width / 2 + position.x, 0), max(width - size.width, 0))
        let y = max(position.y, 0)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// Lugar a guardar para um post-it solto com o canto superior esquerdo em `origin` (medido na área de largura `width`),
    /// já dentro da área, como `frame(for:width:)` o desenharia.
    static func position(forOrigin origin: CGPoint, width: CGFloat) -> CGPoint {
        let placed = frame(for: CGPoint(x: origin.x - width / 2, y: origin.y), width: width)
        return CGPoint(x: placed.minX - width / 2, y: placed.minY)
    }

    /// O retângulo visível (no espaço do conteúdo) passado para o lugar na pasta e recuado meio post-it: o centro dele é o
    /// lugar de um post-it novo que nasce no meio do que está à vista. `area` é a área dos cartões no mesmo espaço.
    static func visibleRectForNewSticky(_ visibleRect: CGRect, area: CGRect) -> CGRect {
        visibleRect.offsetBy(dx: -area.minX - area.width / 2 - size.width / 2, dy: -area.minY - size.height / 2)
    }
}
