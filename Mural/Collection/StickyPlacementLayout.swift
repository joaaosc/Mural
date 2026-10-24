import SwiftUI

/// Camada dos post-its soltos da pasta, por cima das colunas: cada subview vai para o lugar guardado, marcado por
/// `stickyPlacement(_:)`, com o tamanho de `StickyPlacement.size`. A altura cobre o post-it mais baixo para a rolagem
/// alcançá-lo; a largura vem só de fora (a rolagem), nunca do conteúdo, como na `GalleryLayout`, então não há laço de medição.
struct StickyPlacementLayout: Layout {
    struct Cache {
        var frames: [CGRect] = []
        var width: CGFloat?
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.frames.removeAll(keepingCapacity: true)
        cache.width = nil
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? 900
        let frames = frames(width: width, subviews: subviews)
        cache.frames = frames
        cache.width = width
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let frames: [CGRect]
        if cache.width == bounds.width, cache.frames.count == subviews.count {
            frames = cache.frames
        } else {
            frames = self.frames(width: bounds.width, subviews: subviews)
        }
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
        cache.frames.removeAll(keepingCapacity: true)
        cache.width = nil
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
