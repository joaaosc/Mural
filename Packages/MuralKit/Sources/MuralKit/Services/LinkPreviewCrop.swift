import CoreGraphics

/// Recorte da página que vira a imagem de prévia do cartão de link.
public enum LinkPreviewCrop {
    /// Retângulo a capturar na área visível da página: a largura toda, a partir do topo, na proporção pedida.
    ///
    /// As coordenadas são as da área visível (origem no canto de cima à esquerda do que se vê), que é como o
    /// WebKit do macOS lê a região de uma imagem; não dependem da rolagem nem do zoom da página. Se a área for
    /// baixa demais para a proporção com a largura toda, usa a altura toda e centraliza o recorte na horizontal.
    /// - Parameters:
    ///   - size: tamanho da área visível, em pontos.
    ///   - aspectRatio: largura ÷ altura da imagem de prévia.
    /// - Returns: `nil` se a área estiver vazia ou a proporção não for um número positivo.
    public static func region(inViewportOf size: CGSize, aspectRatio: CGFloat) -> CGRect? {
        guard size.width.isFinite, size.height.isFinite, aspectRatio.isFinite,
            size.width > 0, size.height > 0, aspectRatio > 0
        else { return nil }

        let fullWidthHeight = size.width / aspectRatio
        if fullWidthHeight <= size.height {
            return CGRect(x: 0, y: 0, width: size.width, height: fullWidthHeight)
        }
        let width = size.height * aspectRatio
        return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height)
    }
}
