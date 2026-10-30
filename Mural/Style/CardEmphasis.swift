import SwiftUI

extension EnvironmentValues {
    /// Conteúdo esmaecido mantém a miniatura estática, sem filtrar uma camada de vídeo do AppKit.
    @Entry var cardEmphasis = 1.0
}

extension View {
    /// Esmaece um cartão sem deixá-lo transparente.
    ///
    /// A cor do cartão se aproxima da cor do mural na proporção `1 - emphasis`, como fazia a
    /// opacidade, mas o cartão continua sólido: o que está atrás dele (outro cartão, a mídia
    /// guardada atrás da folha da pasta) não aparece através. Com `emphasis` igual a 1, o
    /// cartão fica como está e nada é misturado.
    func cardEmphasis(_ emphasis: Double) -> some View {
        modifier(CardEmphasisEffect(emphasis: emphasis))
    }
}
