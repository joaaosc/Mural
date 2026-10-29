import Foundation

/// Proporção (largura ÷ altura) em que o canto de uma foto encaixa ao ser arrastado, e que o menu "Tamanho" oferece.
/// Os nomes mostrados na tela ficam no app.
public enum ImageProportion: Hashable, Sendable {
    /// A da própria foto: o cartão mostra a imagem inteira, sem recorte.
    case original
    /// Uma proporção fixa, como 4:3 ou 1:1.
    case fixed(width: Int, height: Int)
}
