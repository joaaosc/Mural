import CoreGraphics
import MuralKit
import SwiftUI

/// Fases observáveis da restauração de uma cena. Cada callback carrega o mural e a
/// geração que o iniciou, para que uma janela antiga nunca publique estado noutra.
enum CanvasRestorationPhase: Equatable {
    case loading
    case awaitingLayout
    case applyingZoom
    case applyingPosition
    case ready
}

struct CanvasRestorationToken: Equatable, Sendable {
    let boardID: BoardID
    let generation: UInt64
}

/// Operações geométricas puras do canvas. O ponto persistido está em coordenadas
/// lógicas, não em pontos físicos da janela, portanto sobrevive a resize e zoom.
enum CanvasWorkspaceMath {
    static func logicalCenter(
        contentOffset: CGPoint,
        viewport: CGSize,
        zoom: CGFloat,
        contentInsets: EdgeInsets = EdgeInsets()
    ) -> CGPoint {
        guard zoom > 0 else { return .zero }
        let availableWidth = max(0, viewport.width - contentInsets.leading - contentInsets.trailing)
        let availableHeight = max(0, viewport.height - contentInsets.top - contentInsets.bottom)
        return CGPoint(
            x: (contentOffset.x + contentInsets.leading + availableWidth / 2) / zoom,
            y: (contentOffset.y + contentInsets.top + availableHeight / 2) / zoom
        )
    }

    static func targetOffset(
        logicalCenter: CGPoint,
        zoom: CGFloat,
        viewport: CGSize,
        contentSize: CGSize,
        contentInsets: EdgeInsets = EdgeInsets()
    ) -> CGPoint {
        guard zoom > 0 else { return .zero }
        let availableWidth = max(0, viewport.width - contentInsets.leading - contentInsets.trailing)
        let availableHeight = max(0, viewport.height - contentInsets.top - contentInsets.bottom)
        let proposed = CGPoint(
            x: logicalCenter.x * zoom - contentInsets.leading - availableWidth / 2,
            y: logicalCenter.y * zoom - contentInsets.top - availableHeight / 2
        )
        let maxX = max(0, contentSize.width - viewport.width)
        let maxY = max(0, contentSize.height - viewport.height)
        return CGPoint(
            x: min(max(0, proposed.x), maxX),
            y: min(max(0, proposed.y), maxY)
        )
    }
}

/// Pequena máquina de estados para separar carregamento, aplicação da escala e
/// aplicação da posição. A UI usa-a como barreira contra gravações prematuras.
struct CanvasRestorationStateMachine: Equatable {
    private(set) var phase: CanvasRestorationPhase = .loading
    private(set) var token: CanvasRestorationToken?

    mutating func begin(_ token: CanvasRestorationToken) {
        self.token = token
        phase = .awaitingLayout
    }

    mutating func applyZoom(for token: CanvasRestorationToken) -> Bool {
        guard self.token == token, phase == .awaitingLayout else { return false }
        phase = .applyingZoom
        return true
    }

    mutating func applyPosition(for token: CanvasRestorationToken) -> Bool {
        guard self.token == token, phase == .applyingZoom else { return false }
        phase = .applyingPosition
        return true
    }

    mutating func confirmReady(for token: CanvasRestorationToken) -> Bool {
        guard self.token == token, phase == .applyingPosition else { return false }
        phase = .ready
        return true
    }

    var acceptsPersistence: Bool { phase == .ready }
}
