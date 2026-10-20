import SwiftUI

extension View {
    /// Esmaece um cartão sem deixá-lo transparente.
    ///
    /// A cor do cartão se aproxima da cor do mural na proporção `1 - emphasis`, como fazia a
    /// opacidade, mas o cartão continua sólido: o que está atrás dele (outro cartão, a mídia
    /// guardada atrás da folha da pasta) não aparece através. Com `emphasis` igual a 1, o
    /// cartão fica como está e nada é misturado.
    func cardEmphasis(_ emphasis: Double) -> some View {
        overlay {
            if emphasis < 1 {
                Theme.canvas
                    .opacity(1 - emphasis)
                    // Folga para tingir também a sombra e a mídia que passa da borda da pasta.
                    .padding(-24)
                    // Pinta só onde o cartão já tem tinta, sem mudar a forma nem a opacidade dele.
                    .blendMode(.sourceAtop)
                    .allowsHitTesting(false)
            }
        }
        // Junta as camadas do cartão antes da mistura; sem o grupo, a cor do mural
        // cobriria também o que está em volta do cartão.
        .compositingGroup()
    }
}
