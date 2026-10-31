import SwiftUI

/// Os controles do rodapé da janela se registram aqui, para o miniplayer desviar deles.
nonisolated struct NowPlayingObstacleKey: PreferenceKey {
    static var defaultValue: [Anchor<CGRect>] { [] }

    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    /// Marca esta view como um controle do rodapé, que o miniplayer não deve cobrir.
    func nowPlayingObstacle() -> some View {
        anchorPreference(key: NowPlayingObstacleKey.self, value: .bounds) { [$0] }
    }
}

/// Onde o miniplayer fica no rodapé da janela, em relação aos controles que já estão ali.
struct NowPlayingPlacement: Equatable {
    static let margin: CGFloat = 18
    static let gap: CGFloat = 12
    static let liftGap: CGFloat = 10
    /// Largura da cápsula compacta.
    static let pillWidth: CGFloat = 280
    /// Só os controles que chegam a esta distância do fundo contam como obstáculo.
    static let bottomZone: CGFloat = 140

    let maxWidth: CGFloat
    let bottomPadding: CGFloat
    /// Onde começa a cápsula, na horizontal.
    let originX: CGFloat

    /// A cápsula fica centralizada no rodapé e sobe acima de qualquer controle do rodapé que cruze a faixa que ela ocupa ali.
    init(container: CGSize, obstacles: [CGRect], barWidth: CGFloat = NowPlayingPlacement.pillWidth) {
        let bottom = obstacles.filter { $0.maxY > container.height - Self.bottomZone }
        let width = max(min(barWidth, container.width - 2 * Self.margin), 0)
        let originX = (container.width - width) / 2
        let crossing = bottom.filter { $0.minX < originX + width + Self.gap && $0.maxX > originX - Self.gap }
        maxWidth = width
        self.originX = originX
        bottomPadding = crossing.map(\.minY).min().map { container.height - $0 + Self.liftGap } ?? Self.margin
    }
}
