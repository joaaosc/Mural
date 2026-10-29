import MuralKit
import SwiftUI

extension EnvironmentValues {
    /// Quanto o conteúdo de um cartão cresce junto com o tamanho que a pessoa deu a ele no mural: 1 é o tamanho padrão do tipo
    /// e 2, por exemplo, um cartão com o dobro do lado (a conta é `BoardLayout.contentScale`). O mural e a capa fixam o valor
    /// em cada post-it solto; em qualquer outro lugar (pastas, prévias de pasta) fica em 1, e o cartão se desenha como sempre.
    @Entry var boardContentScale: Double = 1
    @Entry var boardImageShowWhole = false
}

extension View {
    /// Dá ao conteúdo do cartão a escala do tamanho em que ele é mostrado, em relação ao tamanho padrão do tipo dele. Um tipo
    /// que não muda de tamanho tem sempre o padrão e, portanto, escala 1.
    func contentScaled(for item: BoardItem, width: Double, height: Double) -> some View {
        let standard = BoardLayout.cardSize(for: item.kind)
        return environment(
            \.boardContentScale,
            BoardLayout.contentScale(width: width, height: height, defaultWidth: standard.width, defaultHeight: standard.height))
    }
}
