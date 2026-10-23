import MuralKit
import SwiftUI

/// Pedido unidirecional de rolagem. O `ScrollPosition` que recebe o pedido fica
/// como `@State` da view, evitando transformar cada atualização interna do
/// `ScrollView` numa mutação observável do controlador de zoom.
struct CanvasScrollRequest: Equatable {
    let id: UInt64
    let point: CGPoint
}

/// Estado do zoom do mural, compartilhado entre a tela, os controles do canto e o
/// menu Visualizar (via `focusedSceneValue`).
///
/// Durante a pinça só muda `liveScale`, uma escala visual ancorada no ponto entre os
/// dedos; ao soltar, a escala assenta e o zoom real é aplicado uma vez, junto com a
/// rolagem que mantém o mesmo ponto parado na tela.
@MainActor
@Observable
final class CanvasZoomController {
    typealias AnimationRunner = (_ changes: () -> Void, _ completion: @escaping () -> Void) -> Void

    /// Zoom aplicado ao layout do mural.
    private(set) var zoom: CGFloat = 1
    /// Escala visual extra, só durante a pinça e o assentamento.
    private(set) var liveScale: CGFloat = 1
    /// Ponto que fica parado durante a escala visual, em coordenadas do conteúdo ampliado.
    private(set) var liveAnchor: CGPoint = .zero
    private(set) var scrollRequest: CanvasScrollRequest?
    /// Tamanho visível do mural.
    var viewport: CGSize = .zero
    /// Área ocupada pelos cartões, sem zoom.
    var contentExtent: CGSize = .zero
    /// Insets reais reportados pela geometria do ScrollView. Só entra em cálculos; fora
    /// da observação para não notificar a cada quadro de rolagem.
    @ObservationIgnored var contentInsets: EdgeInsets = EdgeInsets()
    /// Retângulo visível em coordenadas do conteúdo, fornecido pelo ScrollGeometry.
    @ObservationIgnored var visibleRect: CGRect = .zero

    /// Lido a cada rolagem; não precisa redesenhar nada, por isso fica fora da observação.
    @ObservationIgnored var scrollOffset: CGPoint = .zero
    @ObservationIgnored var reduceMotion = false
    @ObservationIgnored private var isPinching = false
    @ObservationIgnored private var settleGeneration = 0
    @ObservationIgnored private var pendingTargetZoom: CGFloat?
    @ObservationIgnored private var configuredAtOrigin = false
    @ObservationIgnored private var scrollRequestID: UInt64 = 0
    @ObservationIgnored private let runSettleAnimation: AnimationRunner
    @ObservationIgnored var onWorkspaceChange: ((CanvasWorkspaceState) -> Void)?

    init(
        animationRunner: @escaping AnimationRunner = { changes, completion in
            withAnimation(.smooth(duration: 0.25)) {
                changes()
            } completion: {
                completion()
            }
        }
    ) {
        runSettleAnimation = animationRunner
    }

    /// Zoom que o usuário vê agora, incluindo a pinça em andamento.
    var displayedZoom: CGFloat { zoom * liveScale }

    /// Copia a geometria real do ScrollView. Chamado a cada quadro de rolagem: o tamanho
    /// do viewport (observado pelo canvas) só é atribuído quando muda de fato.
    func apply(_ metrics: CanvasScrollMetrics) {
        if viewport != metrics.containerSize { viewport = metrics.containerSize }
        scrollOffset = metrics.contentOffset
        contentInsets = metrics.contentInsets
        visibleRect = metrics.visibleRect
    }

    /// Configura a escala confirmada e a âncora persistida de uma sessão.
    /// Quando não há centro salvo, pode usar uma âncora inicial baseada no conteúdo.
    func configure(workspace: CanvasWorkspaceState, fallbackAnchor: CGPoint? = nil) {
        invalidatePendingSettle()
        zoom = CanvasZoom.clamped(CGFloat(workspace.confirmedZoom))
        liveScale = 1
        configuredAtOrigin = workspace.isAtOrigin
        if let center = workspace.logicalCenter {
            liveAnchor = CGPoint(x: center.x, y: center.y)
        } else if let fallbackAnchor {
            liveAnchor = fallbackAnchor
        } else {
            liveAnchor = .zero
            requestScroll(to: .zero)
        }
    }

    /// Consolida o alvo aceito antes de uma janela ser fechada. Nunca publica a escala visual.
    @discardableResult
    func prepareToLeave() -> CanvasWorkspaceState {
        let target = pendingTargetZoom ?? zoom
        if pendingTargetZoom != nil {
            let generation = settleGeneration
            commit(targetZoom: target, baseZoom: zoom, anchor: liveAnchor, generation: generation)
        } else {
            liveScale = 1
        }
        return confirmedWorkspace()
    }

    /// Captura apenas o estado confirmado, usando o centro lógico visível.
    func confirmedWorkspace(contentInsets: EdgeInsets? = nil) -> CanvasWorkspaceState {
        let insets = contentInsets ?? self.contentInsets
        let atLeading = abs(scrollOffset.x + insets.leading) <= 1 && abs(scrollOffset.y + insets.top) <= 1
        if configuredAtOrigin && atLeading {
            return CanvasWorkspaceState(confirmedZoom: Double(zoom), anchor: .origin)
        }
        configuredAtOrigin = false
        let center: CGPoint
        if !visibleRect.isEmpty {
            center = CanvasWorkspaceMath.logicalCenter(visibleRect: visibleRect, zoom: zoom)
        } else {
            center = CanvasWorkspaceMath.logicalCenter(
                contentOffset: scrollOffset,
                viewport: viewport,
                zoom: zoom,
                contentInsets: insets)
        }
        if center == .zero && scrollOffset == .zero {
            return CanvasWorkspaceState(confirmedZoom: Double(zoom), anchor: .origin)
        }
        return CanvasWorkspaceState(
            confirmedZoom: Double(zoom),
            anchor: .logicalCenter(BoardPoint(x: center.x, y: center.y))
        )
    }

    // MARK: Pinça

    func pinchChanged(magnification: CGFloat, startLocation: CGPoint) {
        if !isPinching {
            isPinching = true
            invalidatePendingSettle()
            let origin = visibleRect.isEmpty ? scrollOffset : visibleRect.origin
            liveAnchor = CGPoint(x: origin.x + startLocation.x, y: origin.y + startLocation.y)
        }
        liveScale = CanvasZoom.rubberBanded(zoom * magnification) / zoom
    }

    func pinchEnded(magnification: CGFloat) {
        isPinching = false
        settle(to: CanvasZoom.clamped(zoom * magnification))
    }

    // MARK: Comandos

    func zoomIn() { zoom(to: (pendingTargetZoom ?? zoom) * CanvasZoom.step) }
    func zoomOut() { zoom(to: (pendingTargetZoom ?? zoom) / CanvasZoom.step) }
    func actualSize() { zoom(to: 1) }

    /// Mostra todos os cartões, a partir do canto superior esquerdo.
    func fitToWindow() {
        let target = CanvasZoom.fitting(extent: contentExtent, in: viewport)
        invalidatePendingSettle()
        configuredAtOrigin = false
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) {
            zoom = target
            liveScale = 1
            scrollOffset = .zero
            visibleRect = CGRect(origin: .zero, size: viewport)
            requestScroll(to: .zero)
        }
        onWorkspaceChange?(confirmedWorkspace())
    }

    // MARK: Interno

    /// Aproxima ou afasta mantendo parado o centro da janela.
    private func zoom(to target: CGFloat) {
        let origin = visibleRect.isEmpty ? scrollOffset : visibleRect.origin
        liveAnchor = CGPoint(x: origin.x + viewport.width / 2, y: origin.y + viewport.height / 2)
        settle(to: CanvasZoom.clamped(target))
    }

    /// Anima a escala visual até o alvo absoluto e depois aplica o zoom real de uma vez.
    private func settle(to targetZoom: CGFloat) {
        let targetZoom = CanvasZoom.clamped(targetZoom)
        let generation = settleGeneration &+ 1
        settleGeneration = generation
        pendingTargetZoom = targetZoom
        let baseZoom = zoom
        let scale = targetZoom / baseZoom
        let anchor = liveAnchor

        guard !reduceMotion else {
            commit(targetZoom: targetZoom, baseZoom: baseZoom, anchor: anchor, generation: generation)
            return
        }
        runSettleAnimation(
            { [weak self] in self?.liveScale = scale },
            { [weak self] in
                self?.commit(targetZoom: targetZoom, baseZoom: baseZoom, anchor: anchor, generation: generation)
            }
        )
    }

    /// Troca a escala visual pelo zoom real e compensa a rolagem, sem animação: o
    /// resultado na tela é idêntico ao último quadro da escala visual.
    private func commit(targetZoom: CGFloat, baseZoom: CGFloat, anchor: CGPoint, generation: Int) {
        guard settleGeneration == generation else { return }
        let targetZoom = CanvasZoom.clamped(targetZoom)
        let scale = targetZoom / baseZoom
        let offset = CanvasZoom.offset(keeping: anchor, from: scrollOffset, scale: scale)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.scrollContentOffsetAdjustmentBehavior = .disabled
        withTransaction(transaction) {
            zoom = targetZoom
            liveScale = 1
            pendingTargetZoom = nil
            scrollOffset = offset
            visibleRect = CGRect(origin: offset, size: viewport)
            requestScroll(to: offset)
        }
        onWorkspaceChange?(confirmedWorkspace())
    }

    func requestScroll(to point: CGPoint) {
        scrollRequestID &+= 1
        scrollRequest = CanvasScrollRequest(id: scrollRequestID, point: point)
    }

    private func invalidatePendingSettle() {
        settleGeneration &+= 1
        pendingTargetZoom = nil
    }
}
