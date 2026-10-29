import SwiftUI

extension View {
    /// Mantém a chamada compatível e deixa o sistema escolher quando mostrar as barras,
    /// respeitando a preferência de rolagem da pessoa.
    func discreetScrollIndicators(_ axes: Axis.Set = .vertical) -> some View {
        scrollIndicators(.automatic, axes: axes)
    }
}
