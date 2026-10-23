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
                let size = BoardLayout.cardSize(for: item.kind)
                let origin = layout.coverPoint(for: item.position)
                CardView(item: item, model: model)
                    .frame(width: size.width, height: size.height)
                    // A escala parte do canto de cima, à esquerda, e o deslocamento leva esse canto ao lugar da capa.
                    .scaleEffect(layout.scale, anchor: .topLeading)
                    .offset(x: origin.x, y: origin.y)
            }
            // Como no mural, os textos livres ficam por cima dos cartões.
            ForEach(layout.freeTexts) { freeText in
                let origin = layout.coverPoint(for: freeText.position)
                CoverFreeText(text: freeText.text)
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

/// Texto livre na capa: o mesmo quadrado e o mesmo texto do mural (`BoardFreeTextView`), com um branco translúcido
/// no lugar do vidro.
private struct CoverFreeText: View {
    let text: String

    var body: some View {
        Text(text.isEmpty ? "Texto livre" : text)
            .font(.system(size: 20))
            .multilineTextAlignment(.center)
            .lineLimit(10)
            .minimumScaleFactor(0.65)
            .frame(width: BoardLayout.freeTextSide, height: BoardLayout.freeTextSide)
            .clipped()
            .background(.white.opacity(0.55), in: .rect(cornerRadius: 24))
    }
}
