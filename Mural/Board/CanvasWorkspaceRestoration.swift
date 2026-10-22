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

struct CanvasScrollMetrics: Equatable {
    let contentOffset: CGPoint
    let containerSize: CGSize
    let contentSize: CGSize
    let contentInsets: EdgeInsets
    let visibleRect: CGRect

    init(
        contentOffset: CGPoint,
        containerSize: CGSize,
        contentSize: CGSize,
        contentInsets: EdgeInsets = EdgeInsets(),
        visibleRect: CGRect? = nil
    ) {
        self.contentOffset = contentOffset
        self.containerSize = containerSize
        self.contentSize = contentSize
        self.contentInsets = contentInsets
        self.visibleRect = visibleRect ?? CGRect(origin: contentOffset, size: containerSize)
    }

    init(_ geometry: ScrollGeometry) {
        contentOffset = geometry.contentOffset
        containerSize = geometry.containerSize
        contentSize = geometry.contentSize
        contentInsets = geometry.contentInsets
        visibleRect = geometry.visibleRect
    }
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

    static func logicalCenter(visibleRect: CGRect, zoom: CGFloat) -> CGPoint {
        guard zoom > 0 else { return .zero }
        return CGPoint(x: visibleRect.midX / zoom, y: visibleRect.midY / zoom)
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
        // ScrollGeometry reports offsets relative to the inset content. The
        // reachable interval therefore starts at the leading inset and ends
        // after the trailing inset, rather than assuming a zero-origin scroll.
        let minX = -contentInsets.leading
        let minY = -contentInsets.top
        let maxX = max(minX, contentSize.width - viewport.width + contentInsets.trailing)
        let maxY = max(minY, contentSize.height - viewport.height + contentInsets.bottom)
        return CGPoint(
            x: min(max(minX, proposed.x), maxX),
            y: min(max(minY, proposed.y), maxY)
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

    /// Saída de emergência do watchdog: aceita a geometria alcançada em vez de deixar o
    /// canvas sem interação. Só vale depois que a restauração já recebeu layout real.
    mutating func forceReady(for token: CanvasRestorationToken) -> Bool {
        guard self.token == token, phase == .applyingZoom || phase == .applyingPosition else { return false }
        phase = .ready
        return true
    }

    var acceptsPersistence: Bool { phase == .ready }
}
