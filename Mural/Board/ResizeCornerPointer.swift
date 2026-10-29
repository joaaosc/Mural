import MuralKit
import SwiftUI

/// Troca o cursor pelo de redimensionar quando o ponteiro está sobre um dos quatro cantos do elemento.
///
/// Não há zonas invisíveis sobre os cantos: elas roubariam o clique, o duplo clique e o menu do cartão. O ponteiro é lido com
/// `onContinuousHover` no próprio elemento, e o canto fica num `@State` local que só é escrito quando muda, para o mural não
/// ser redesenhado a cada movimento do mouse. O arrasto em si continua sendo do gesto de mover do elemento (`BoardCanvasView`),
/// que decide pelo canto com a mesma conta (`ResizeCornerHit`).
struct ResizeCornerPointer: ViewModifier {
    /// Tamanho mostrado do elemento, em pontos do mural.
    let size: BoardSize
    let zoom: CGFloat
    /// Falso enquanto algo é movido, com o seletor de ⌘ aberto ou com o retângulo de Shift: o cursor volta ao normal.
    let isEnabled: Bool

    @State private var corner: ResizeCorner?

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    guard isEnabled else { return update(nil) }
                    update(ResizeCornerHit.corner(at: point, size: CGSize(width: size.width, height: size.height), zoom: zoom))
                case .ended:
                    update(nil)
                }
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled { update(nil) }
            }
            .pointerStyle(corner.map { .frameResize(position: $0.pointerPosition) })
    }

    private func update(_ next: ResizeCorner?) {
        if corner != next { corner = next }
    }
}

extension View {
    /// Mostra o cursor de redimensionar nos quatro cantos do elemento (`ResizeCornerPointer`).
    func resizeCornerPointer(size: BoardSize, zoom: CGFloat, isEnabled: Bool) -> some View {
        modifier(ResizeCornerPointer(size: size, zoom: zoom, isEnabled: isEnabled))
    }
}
