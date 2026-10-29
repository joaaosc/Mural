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

/// Onde o miniplayer fica no canto inferior esquerdo: ao lado dos controles do rodapé quando cabe a forma com todos os
/// botões, ou acima deles. A forma compacta, sem Faixa anterior e Parar, fica para quando a própria janela é estreita.
struct NowPlayingPlacement: Equatable {
    static let margin: CGFloat = 18
    static let gap: CGFloat = 12
    static let liftGap: CGFloat = 10
    /// Largura da forma média do miniplayer (título curto e os quatro botões): menos que isso ao lado da barra, ele sobe.
    static let preferredWidth: CGFloat = 320
    static let maximumWidth: CGFloat = 420
    /// Só os controles que chegam a esta distância do fundo contam como obstáculo.
    static let bottomZone: CGFloat = 140

    let maxWidth: CGFloat
    let bottomPadding: CGFloat

    init(container: CGSize, obstacles: [CGRect]) {
        let bottom = obstacles.filter { $0.maxY > container.height - Self.bottomZone }
        let free = (bottom.map(\.minX).min() ?? container.width) - Self.gap - Self.margin
        let room = min(Self.maximumWidth, free)
        if room >= Self.preferredWidth {
            maxWidth = room
            bottomPadding = Self.margin
        } else {
            let top = bottom.map(\.minY).min() ?? container.height
            bottomPadding = container.height - top + Self.liftGap
            maxWidth = min(Self.maximumWidth, container.width - 2 * Self.margin)
        }
    }
}
