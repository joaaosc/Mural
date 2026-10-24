import SwiftUI

/// Layout da pasta: aplica `GalleryArrangement` aos cartões, cada um marcado com a
/// sua faixa por `galleryLane(_:)`. A largura vem só de fora (a rolagem), nunca do
/// conteúdo, então não há laço de medição.
struct GalleryLayout: Layout {
    var metrics = GalleryArrangement.Metrics()

    struct Cache {
        var arrangement: GalleryArrangement?
        var width: CGFloat?
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(arrangement: nil, width: nil)
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.arrangement = nil
        cache.width = nil
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? 900
        let arranged = makeArrangement(width: width, subviews: subviews)
        cache.arrangement = arranged
        cache.width = width
        return arranged.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let arrangement: GalleryArrangement
        if let cached = cache.arrangement, cache.width == bounds.width, cached.frames.count == subviews.count {
            arrangement = cached
        } else {
            arrangement = makeArrangement(width: bounds.width, subviews: subviews)
        }
        for (subview, frame) in zip(subviews, arrangement.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
        // O cache é intencionalmente só do par medida-posicionamento: mudanças de conteúdo
        // não podem reaproveitar uma geometria de outro ciclo.
        cache.arrangement = nil
        cache.width = nil
    }

    private func makeArrangement(width: CGFloat, subviews: Subviews) -> GalleryArrangement {
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
