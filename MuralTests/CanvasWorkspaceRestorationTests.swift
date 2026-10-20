import CoreGraphics
import Foundation
import MuralKit
import Testing

@testable import Mural

@Suite("Restauração do canvas")
@MainActor
struct CanvasWorkspaceRestorationTests {
    private let boardID = BoardID(rawValue: UUID())

    @Test("Callbacks de mural e geração antigos são ignorados")
    func staleCallbacksAreIgnored() {
        var machine = CanvasRestorationStateMachine()
        let token = CanvasRestorationToken(boardID: boardID, generation: 7)
        let stale = CanvasRestorationToken(boardID: BoardID(), generation: 6)
        machine.begin(token)

        let staleZoom = machine.applyZoom(for: stale)
        #expect(staleZoom == false)
        #expect(machine.phase == .awaitingLayout)
        let appliedZoom = machine.applyZoom(for: token)
        #expect(appliedZoom)
        let appliedPosition = machine.applyPosition(for: token)
        #expect(appliedPosition)
        let staleReady = machine.confirmReady(for: stale)
        #expect(staleReady == false)
        #expect(machine.phase == .applyingPosition)
        let ready = machine.confirmReady(for: token)
        #expect(ready)
        #expect(machine.acceptsPersistence)
    }

    @Test("Centro lógico preserva o viewport com tolerância de um ponto")
    func centerRoundTrip() {
        let center = CGPoint(x: 920, y: 540)
        let viewport = CGSize(width: 800, height: 600)
        let zoom: CGFloat = 1.25
        let content = CGSize(width: 2_800, height: 2_200)
        let offset = CanvasWorkspaceMath.targetOffset(
            logicalCenter: center, zoom: zoom, viewport: viewport, contentSize: content)
        let restored = CanvasWorkspaceMath.logicalCenter(contentOffset: offset, viewport: viewport, zoom: zoom)

        #expect(abs(restored.x - center.x) <= 1)
        #expect(abs(restored.y - center.y) <= 1)
    }

    @Test("Resize usa centro lógico e limita ao alcance real")
    func resizeClampsToReachableContent() {
        let offset = CanvasWorkspaceMath.targetOffset(
            logicalCenter: CGPoint(x: 10_000, y: 10_000),
            zoom: 1,
            viewport: CGSize(width: 900, height: 700),
            contentSize: CGSize(width: 1_200, height: 900)
        )

        #expect(offset == CGPoint(x: 300, y: 200))
    }

    @Test("Cem ciclos não acumulam drift")
    func repeatedCaptureRestoreDoesNotDrift() {
        let viewport = CGSize(width: 900, height: 700)
        let content = CGSize(width: 3_400, height: 2_800)
        let zoom: CGFloat = 1.1
        var center = CGPoint(x: 1_200, y: 980)

        for _ in 0..<100 {
            let offset = CanvasWorkspaceMath.targetOffset(
                logicalCenter: center, zoom: zoom, viewport: viewport, contentSize: content)
            center = CanvasWorkspaceMath.logicalCenter(
                contentOffset: offset, viewport: viewport, zoom: zoom)
        }

        #expect(abs(center.x - 1_200) <= 1)
        #expect(abs(center.y - 980) <= 1)
    }
}
