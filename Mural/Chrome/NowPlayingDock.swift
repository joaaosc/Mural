import SwiftUI

/// Em qual dos três pontos do rodapé o miniplayer fica encaixado.
enum NowPlayingDock: String, CaseIterable, Sendable {
    case leading
    case center
    case trailing

    /// Alinhamento horizontal do miniplayer (e do cartão expandido) neste ponto.
    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    /// Alinhamento da cápsula no rodapé da janela.
    var bottomAlignment: Alignment {
        switch self {
        case .leading: .bottomLeading
        case .center: .bottom
        case .trailing: .bottomTrailing
        }
    }

    /// O ponto mais perto de `midX`, a posição horizontal do meio da cápsula.
    static func nearest(toMidX midX: CGFloat, container: CGSize, barWidth: CGFloat) -> NowPlayingDock {
        allCases.min { lhs, rhs in
            abs(NowPlayingPlacement.originX(for: lhs, container: container, width: barWidth) + barWidth / 2 - midX)
                < abs(NowPlayingPlacement.originX(for: rhs, container: container, width: barWidth) + barWidth / 2 - midX)
        } ?? .leading
    }
}
