import SwiftUI

/// Layout da pasta: aplica `GalleryArrangement` aos cartões, cada um marcado com a
/// sua faixa por `galleryLane(_:)`. A largura vem só de fora (a rolagem), nunca do
/// conteúdo, então não há laço de medição.
struct GalleryLayout: Layout {
    var metrics = GalleryArrangement.Metrics()

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width ?? 900, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrangement(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, arrangement.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func arrangement(width: CGFloat, subviews: Subviews) -> GalleryArrangement {
        GalleryArrangement(width: width, lanes: subviews.map { $0[GalleryLaneKey.self] }, metrics: metrics) { index, columnWidth in
            subviews[index].sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
        }
    }
}

private nonisolated struct GalleryLaneKey: LayoutValueKey {
    static let defaultValue = GalleryLane.media
}

extension View {
    /// Faixa do cartão dentro de `GalleryLayout`.
    func galleryLane(_ lane: GalleryLane) -> some View {
        layoutValue(key: GalleryLaneKey.self, value: lane)
    }
}
