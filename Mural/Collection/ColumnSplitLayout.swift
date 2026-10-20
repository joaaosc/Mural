import SwiftUI

/// Divide a largura recebida entre os filhos em proporções fixas (por exemplo, 62% e 38%).
///
/// A largura vem só de quem está por fora (a rolagem), nunca do conteúdo,
/// o que evita o laço de medição em que o conteúdo empurra a janela e a janela
/// empurra o conteúdo.
struct ColumnSplitLayout: Layout {
    var fractions: [CGFloat]
    var spacing: CGFloat = 28

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 900
        let widths = columnWidths(total: width, count: subviews.count)
        let height =
            zip(subviews, widths)
            .map { subview, columnWidth in subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }
            .max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = columnWidths(total: bounds.width, count: subviews.count)
        var x = bounds.minX
        for (subview, columnWidth) in zip(subviews, widths) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: columnWidth, height: nil))
            x += columnWidth + spacing
        }
    }

    private func columnWidths(total: CGFloat, count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        let usable = max(total - spacing * CGFloat(count - 1), 0)
        let shares = (0..<count).map { $0 < fractions.count ? fractions[$0] : 1 }
        let sum = shares.reduce(0, +)
        return shares.map { usable * $0 / sum }
    }
}
