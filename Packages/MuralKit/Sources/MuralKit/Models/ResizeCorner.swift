import Foundation

/// O canto de um elemento do mural que a pessoa arrasta para mudar o tamanho. O canto oposto fica parado.
public enum ResizeCorner: CaseIterable, Hashable, Sendable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    /// Se o canto fica na borda esquerda: arrastar para a esquerda aumenta a largura e a origem anda junto com o ponteiro.
    public var isLeading: Bool { self == .topLeading || self == .bottomLeading }

    /// Se o canto fica na borda de cima: arrastar para cima aumenta a altura e a origem anda junto com o ponteiro.
    public var isTop: Bool { self == .topLeading || self == .topTrailing }
}
