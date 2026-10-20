import SwiftUI

extension View {
    /// Troca as barras de rolagem do sistema por indicadores finos que só aparecem
    /// enquanto há rolagem. Com um mouse conectado, o macOS mostra barras largas e fixas;
    /// estes indicadores têm o visual do trackpad em qualquer caso. São só informativos:
    /// a rolagem continua pelo trackpad, pela roda do mouse e pelo teclado.
    func discreetScrollIndicators(_ axes: Axis.Set = .vertical) -> some View {
        modifier(DiscreetScrollIndicators(axes: axes))
    }
}

private struct DiscreetScrollIndicators: ViewModifier {
    let axes: Axis.Set

    @State private var metrics = ScrollMetrics()
    @State private var isScrolling = false

    func body(content: Content) -> some View {
        content
            .scrollIndicators(.never, axes: axes)
            .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
                ScrollMetrics(offset: geometry.contentOffset, content: geometry.contentSize, container: geometry.containerSize)
            } action: { _, new in
                metrics = new
            }
            .onScrollPhaseChange { _, phase in isScrolling = phase.isScrolling }
            .overlay {
                ScrollIndicatorBars(metrics: metrics, axes: axes)
                    .opacity(isScrolling ? 1 : 0)
                    .animation(isScrolling ? .easeOut(duration: 0.12) : .easeOut(duration: 0.5).delay(0.6), value: isScrolling)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

/// O que os indicadores precisam saber da rolagem.
private struct ScrollMetrics: Equatable {
    var offset = CGPoint.zero
    var content = CGSize.zero
    var container = CGSize.zero
}

private struct ScrollIndicatorBars: View {
    let metrics: ScrollMetrics
    let axes: Axis.Set

    private let thickness: CGFloat = 5
    private let inset: CGFloat = 3
    private let minimumLength: CGFloat = 32

    private var showsVertical: Bool {
        axes.contains(.vertical) && metrics.content.height > metrics.container.height + 1
    }

    private var showsHorizontal: Bool {
        axes.contains(.horizontal) && metrics.content.width > metrics.container.width + 1
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if showsVertical {
                let track = metrics.container.height - inset * 2 - (showsHorizontal ? thickness + inset : 0)
                let thumb = thumb(track: track, visible: metrics.container.height, total: metrics.content.height, offset: metrics.offset.y)
                Capsule()
                    .fill(.primary.opacity(0.35))
                    .frame(width: thickness, height: thumb.length)
                    .offset(x: metrics.container.width - thickness - inset, y: inset + thumb.position)
            }
            if showsHorizontal {
                let track = metrics.container.width - inset * 2 - (showsVertical ? thickness + inset : 0)
                let thumb = thumb(track: track, visible: metrics.container.width, total: metrics.content.width, offset: metrics.offset.x)
                Capsule()
                    .fill(.primary.opacity(0.35))
                    .frame(width: thumb.length, height: thickness)
                    .offset(x: inset + thumb.position, y: metrics.container.height - thickness - inset)
            }
        }
        .frame(width: metrics.container.width, height: metrics.container.height, alignment: .topLeading)
    }

    /// Comprimento proporcional à parte visível e posição proporcional à rolagem.
    private func thumb(track: CGFloat, visible: CGFloat, total: CGFloat, offset: CGFloat) -> (length: CGFloat, position: CGFloat) {
        let length = min(max(track * visible / total, minimumLength), track)
        let progress = min(max(offset / max(total - visible, 1), 0), 1)
        return (length, (track - length) * progress)
    }
}
