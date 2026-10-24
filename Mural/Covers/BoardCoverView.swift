import MuralKit
import SwiftUI

/// A capa de um mural: o mural inteiro, reduzido, com os próprios cartões.
///
/// O enquadramento (escala e posição de cada cartão) vem de `BoardCoverLayout`; aqui só se desenha. Os cartões são os
/// mesmos do mural (`CardView`), então a capa muda junto com eles. Fica de fora o que o `ImageRenderer` não desenha
/// (vidro e material): o texto livre ganha um branco translúcido no lugar do vidro, e a legenda do cartão não entra.
struct BoardCoverView: View {
    /// Tamanho da capa, em pontos. `BoardCoverRenderer` desenha em 2x.
    static let size = CGSize(width: 320, height: 200)

    let layout: BoardCoverLayout
    let model: BoardModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Na janela o mural é vidro e mostra o que há atrás; a capa não tem nada atrás, então leva o cinza sólido.
            Theme.canvas
            ForEach(layout.items) { item in
                let size = BoardLayout.size(of: item)
                let origin = layout.coverPoint(for: item.position)
                CardView(item: item, model: model)
                    // O post-it com tamanho escolhido leva a letra e a margem proporcionais, como no mural.
                    .contentScaled(for: item, width: size.width, height: size.height)
                    .frame(width: size.width, height: size.height)
                    // A escala parte do canto de cima, à esquerda, e o deslocamento leva esse canto ao lugar da capa.
                    .scaleEffect(layout.scale, anchor: .topLeading)
                    .offset(x: origin.x, y: origin.y)
            }
            // Como no mural, os textos livres ficam por cima dos cartões.
            ForEach(layout.freeTexts) { freeText in
                let origin = layout.coverPoint(for: freeText.position)
                let size = BoardLayout.size(of: freeText)
                CoverFreeText(text: freeText.text, size: BoardSize(width: size.width, height: size.height))
                    .scaleEffect(layout.scale, anchor: .topLeading)
                    .offset(x: origin.x, y: origin.y)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .clipped()
        // Capas sempre claras, como fotos: ficam guardadas em disco e não seguem a aparência de quem as vê.
        .environment(\.colorScheme, .light)
    }
}

/// Texto livre na capa: a mesma caixa (no tamanho do mural) e o mesmo texto do mural (`BoardFreeTextView`), com um branco
/// translúcido no lugar do vidro.
private struct CoverFreeText: View {
    let text: String
    /// Tamanho do texto no mural, em pontos do mural.
    let size: BoardSize

    var body: some View {
        Text(text.isEmpty ? "Texto livre" : text)
            .font(.system(size: BoardFreeTextView.fontSize(for: size)))
            .multilineTextAlignment(.center)
            .lineLimit(10)
            .minimumScaleFactor(0.65)
            .frame(width: size.width, height: size.height)
            .clipped()
            .background(.white.opacity(0.55), in: .rect(cornerRadius: 24))
    }
}
