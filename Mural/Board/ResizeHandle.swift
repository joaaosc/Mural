import MuralKit
import SwiftUI

/// Alça de redimensionar sobre o canto inferior direito de um post-it, de uma foto ou de um texto livre no mural. É a única marca
/// visível: os outros três cantos redimensionam do mesmo jeito, só que sem desenho, e mostram o cursor de redimensionar quando o
/// ponteiro passa por eles (`ResizeCornerPointer`).
///
/// A alça só desenha o círculo e troca o ponteiro. Quem muda o tamanho é o gesto de mover do próprio elemento
/// (`BoardCanvasView`), que olha onde o arrasto começou: dentro do quadrado de um canto, o arrasto redimensiona; fora dele, move.
/// Por isso a alça não tem gesto próprio (o gesto do pai teria prioridade de qualquer jeito), e um arrasto que começa nela sobe
/// até o gesto do elemento.
///
/// O círculo e o quadrado do canto têm o mesmo tamanho na tela em qualquer zoom: a alça é desenhada em pontos do mural e
/// encolhida por `1 / zoom`, e o gesto mede o quadrado em `cornerSide / zoom` pontos do mural.
struct ResizeHandle: View {
    /// Zoom do mural, para a alça desfazer a ampliação e ficar do mesmo tamanho na tela.
    let zoom: CGFloat

    /// Lado, em pontos de tela, do quadrado do canto em que um arrasto redimensiona. O círculo fica dentro dele.
    static let cornerSide: CGFloat = 18
    /// Diâmetro, em pontos de tela, do círculo desenhado.
    static let diameter: CGFloat = 9

    var body: some View {
        Circle()
            .fill(.white.opacity(0.7))
            .overlay { Circle().strokeBorder(.black.opacity(0.2), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
            .frame(width: Self.diameter, height: Self.diameter)
            // O quadrado inteiro do canto recebe o clique: um clique ao lado do círculo não abre o cartão por baixo.
            .frame(width: Self.cornerSide, height: Self.cornerSide)
            .contentShape(.rect)
            .scaleEffect(1 / zoom, anchor: .bottomTrailing)
            .pointerStyle(.frameResize(position: .bottomTrailing))
            .accessibilityHidden(true)
    }
}

extension View {
    /// Põe a alça de redimensionar sobre o canto inferior direito. Vem antes do gesto de mover do elemento, para o arrasto que
    /// começa nela chegar a esse gesto.
    func resizeHandle(isVisible: Bool, zoom: CGFloat) -> some View {
        overlay(alignment: .bottomTrailing) {
            if isVisible { ResizeHandle(zoom: zoom) }
        }
    }
}

#Preview("Alça", traits: .fixedLayout(width: 260, height: 160)) {
    ZStack {
        Theme.sticky(.yellow)
            .frame(width: 110, height: 110)
            .resizeHandle(isVisible: true, zoom: 1)
        Theme.sticky(.pink)
            .frame(width: 60, height: 60)
            .resizeHandle(isVisible: true, zoom: 1)
            .offset(x: 100)
    }
    .padding(40)
    .background(Theme.canvas)
}
