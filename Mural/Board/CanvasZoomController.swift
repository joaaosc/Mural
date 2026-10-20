import SwiftUI

/// Estado do zoom do mural, compartilhado entre a tela, os controles do canto e o
/// menu Visualizar (via `focusedSceneValue`).
///
/// Durante a pinça só muda `liveScale`, uma escala visual ancorada no ponto entre os
/// dedos; ao soltar, a escala assenta e o zoom real é aplicado uma vez, junto com a
/// rolagem que mantém o mesmo ponto parado na tela.
@MainActor
@Observable
final class CanvasZoomController {
    /// Zoom aplicado ao layout do mural.
    private(set) var zoom: CGFloat = 1
    /// Escala visual extra, só durante a pinça e o assentamento.
    private(set) var liveScale: CGFloat = 1
    /// Ponto que fica parado durante a escala visual, em coordenadas do conteúdo ampliado.
    private(set) var liveAnchor: CGPoint = .zero
    var scrollPosition = ScrollPosition()
    /// Tamanho visível do mural.
    var viewport: CGSize = .zero
    /// Área ocupada pelos cartões, sem zoom.
    var contentExtent: CGSize = .zero

    /// Lido a cada rolagem; não precisa redesenhar nada, por isso fica fora da observação.
    @ObservationIgnored var scrollOffset: CGPoint = .zero
    @ObservationIgnored var reduceMotion = false
    @ObservationIgnored private var isPinching = false

    /// Zoom que o usuário vê agora, incluindo a pinça em andamento.
    var displayedZoom: CGFloat { zoom * liveScale }

    // MARK: Pinça

    func pinchChanged(magnification: CGFloat, startLocation: CGPoint) {
        if !isPinching {
            isPinching = true
            liveAnchor = CGPoint(x: scrollOffset.x + startLocation.x, y: scrollOffset.y + startLocation.y)
        }
        liveScale = CanvasZoom.rubberBanded(zoom * magnification) / zoom
    }

    func pinchEnded(magnification: CGFloat) {
        isPinching = false
        settle(scale: CanvasZoom.clamped(zoom * magnification) / zoom)
    }

    // MARK: Comandos

    func zoomIn() { zoom(to: zoom * CanvasZoom.step) }
    func zoomOut() { zoom(to: zoom / CanvasZoom.step) }
    func actualSize() { zoom(to: 1) }

    /// Mostra todos os cartões, a partir do canto superior esquerdo.
    func fitToWindow() {
        let target = CanvasZoom.fitting(extent: contentExtent, in: viewport)
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) {
            zoom = target
            scrollPosition.scrollTo(point: .zero)
        }
    }

    // MARK: Interno

    /// Aproxima ou afasta mantendo parado o centro da janela.
    private func zoom(to target: CGFloat) {
        liveAnchor = CGPoint(x: scrollOffset.x + viewport.width / 2, y: scrollOffset.y + viewport.height / 2)
        settle(scale: CanvasZoom.clamped(target) / zoom)
    }

    /// Anima a escala visual até `scale` e depois aplica o zoom real de uma vez.
    private func settle(scale: CGFloat) {
        guard !reduceMotion else {
            commit(scale: scale)
            return
        }
        withAnimation(.smooth(duration: 0.25)) {
            liveScale = scale
        } completion: { [weak self] in
            self?.commit(scale: scale)
        }
    }

    /// Troca a escala visual pelo zoom real e compensa a rolagem, sem animação: o
    /// resultado na tela é idêntico ao último quadro da escala visual.
    private func commit(scale: CGFloat) {
        let offset = CanvasZoom.offset(keeping: liveAnchor, from: scrollOffset, scale: scale)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.scrollContentOffsetAdjustmentBehavior = .disabled
        withTransaction(transaction) {
            zoom *= scale
            liveScale = 1
            scrollPosition.scrollTo(point: offset)
        }
    }
}
