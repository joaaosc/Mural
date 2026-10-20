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

/// Cada indicador é uma barrinha presa à sua borda, e não uma camada do tamanho da
/// rolagem: uma camada assim, mesmo transparente e sem cliques, encobria o conteúdo para
/// a acessibilidade (leitura de tela, Controle por Voz e testes de interface).
private struct DiscreetScrollIndicators: ViewModifier {
    let axes: Axis.Set

    @State private var metrics = ScrollMetrics()
    @State private var isScrolling = false

    private let thickness: CGFloat = 5
    private let inset: CGFloat = 3

    func body(content: Content) -> some View {
        content
            .scrollIndicators(.never, axes: axes)
            .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
                ScrollMetrics(offset: geometry.contentOffset, content: geometry.contentSize, container: geometry.containerSize)
            } action: { _, new in
                metrics = new
            }
            .onScrollPhaseChange { _, phase in isScrolling = phase.isScrolling }
            .overlay(alignment: .topTrailing) {
                if let thumb = metrics.verticalThumb(axes: axes, inset: inset, reserve: thickness + inset) {
                    indicator(width: thickness, height: thumb.length)
                        .offset(x: -inset, y: inset + thumb.position)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let thumb = metrics.horizontalThumb(axes: axes, inset: inset, reserve: thickness + inset) {
                    indicator(width: thumb.length, height: thickness)
                        .offset(x: inset + thumb.position, y: -inset)
                }
            }
    }

    private func indicator(width: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(.primary.opacity(0.35))
            .frame(width: width, height: height)
            .opacity(isScrolling ? 1 : 0)
            .animation(isScrolling ? .easeOut(duration: 0.12) : .easeOut(duration: 0.5).delay(0.6), value: isScrolling)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// O que os indicadores precisam saber da rolagem.
private struct ScrollMetrics: Equatable {
    var offset = CGPoint.zero
    var content = CGSize.zero
    var container = CGSize.zero

    private static let minimumLength: CGFloat = 32

    private var scrollsVertically: Bool { content.height > container.height + 1 }
    private var scrollsHorizontally: Bool { content.width > container.width + 1 }

    func verticalThumb(axes: Axis.Set, inset: CGFloat, reserve: CGFloat) -> (length: CGFloat, position: CGFloat)? {
        guard axes.contains(.vertical), scrollsVertically else { return nil }
        let track = container.height - inset * 2 - (axes.contains(.horizontal) && scrollsHorizontally ? reserve : 0)
        return Self.thumb(track: track, visible: container.height, total: content.height, offset: offset.y)
    }

    func horizontalThumb(axes: Axis.Set, inset: CGFloat, reserve: CGFloat) -> (length: CGFloat, position: CGFloat)? {
        guard axes.contains(.horizontal), scrollsHorizontally else { return nil }
        let track = container.width - inset * 2 - (axes.contains(.vertical) && scrollsVertically ? reserve : 0)
        return Self.thumb(track: track, visible: container.width, total: content.width, offset: offset.x)
    }

    /// Comprimento proporcional à parte visível e posição proporcional à rolagem.
    private static func thumb(track: CGFloat, visible: CGFloat, total: CGFloat, offset: CGFloat) -> (length: CGFloat, position: CGFloat) {
        let length = min(max(track * visible / total, minimumLength), track)
        let progress = min(max(offset / max(total - visible, 1), 0), 1)
        return (length, (track - length) * progress)
    }
}
