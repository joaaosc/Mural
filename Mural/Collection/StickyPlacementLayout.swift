import SwiftUI

/// Camada dos post-its soltos da pasta, por cima das colunas: cada subview vai para o lugar guardado, marcado por
/// `stickyPlacement(_:)`, com o tamanho de `StickyPlacement.size`. A altura cobre o post-it mais baixo para a rolagem
/// alcançá-lo; a largura vem só de fora (a rolagem), nunca do conteúdo, como na `GalleryLayout`, então não há laço de medição.
struct StickyPlacementLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 900
        return CGSize(width: width, height: frames(width: width, subviews: subviews).map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        subviews.map { StickyPlacement.frame(for: $0[StickyPlacementKey.self], width: width) }
    }
}

private nonisolated struct StickyPlacementKey: LayoutValueKey {
    static let defaultValue = CGPoint.zero
}

extension View {
    /// Lugar guardado do post-it dentro de `StickyPlacementLayout`.
    func stickyPlacement(_ position: CGPoint) -> some View {
        layoutValue(key: StickyPlacementKey.self, value: position)
    }
}
