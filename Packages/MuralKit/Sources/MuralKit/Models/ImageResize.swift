import Foundation

/// O que o arrasto do canto de uma foto dá agora: o tamanho e, quando ele encaixou, a proporção em que encaixou.
public struct ImageResize: Equatable, Sendable {
    /// Tamanho já preso aos limites e em pontos inteiros.
    public let size: BoardSize
    /// A proporção em que o tamanho encaixou; `nil` quando o canto acompanha o ponteiro livremente.
    public let proportion: ImageProportion?

    public init(size: BoardSize, proportion: ImageProportion?) {
        self.size = size
        self.proportion = proportion
    }
}
