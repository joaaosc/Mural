import AppKit
import SwiftUI

/// A conta do gesto de dois dedos que troca de mural na vitrine: quantos passos um deslocamento horizontal vale.
///
/// Fica separada da `NSView` para ser testada sem eventos de verdade. O sentido é o do conteúdo, como o usuário o vê
/// mover: arrastar o conteúdo para a esquerda (delta negativo) mostra o mural da direita (+1).
nonisolated struct SwipeAccumulator: Equatable, Sendable {
    /// Quanto o conteúdo precisa andar, em pontos, para valer um passo no trackpad. Ele manda muitos deltas pequenos, por
    /// isso o limiar é de deslocamento, e não de eventos.
    static let preciseThreshold: CGFloat = 40

    /// O deslocamento do gesto que ainda não virou passo: a sobra do último passo dado, com o sinal do arrasto.
    private(set) var travelled: CGFloat = 0

    /// Se a rolagem é do gesto da vitrine: a que não é mais vertical que horizontal. Zero em horizontal não é gesto
    /// (por exemplo o evento que só marca o fim da rolagem), então segue adiante para quem rola na vertical.
    static func isHorizontal(deltaX: CGFloat, deltaY: CGFloat) -> Bool {
        deltaX != 0 && abs(deltaX) >= abs(deltaY)
    }

    /// Soma um evento de rolagem e devolve quantos passos dar: positivo vai para o mural seguinte; negativo, para o
    /// anterior.
    ///
    /// - Parameters:
    ///   - deltaX: o delta horizontal, com o sentido do conteúdo (o AppKit já aplica a preferência de rolagem natural).
    ///   - deltaY: o delta vertical, só para descartar a rolagem que é mais vertical que horizontal.
    ///   - isPrecise: `true` no trackpad, que manda deltas em pontos; `false` na roda de mouse, em que cada evento é um
    ///     passo.
    mutating func add(deltaX: CGFloat, deltaY: CGFloat, isPrecise: Bool) -> Int {
        guard deltaX.isFinite, deltaY.isFinite, Self.isHorizontal(deltaX: deltaX, deltaY: deltaY) else { return 0 }
        guard isPrecise else { return deltaX < 0 ? 1 : -1 }

        travelled += deltaX
        let count = Int(abs(travelled) / Self.preciseThreshold)
        guard count > 0 else { return 0 }
        // Desconta o limiar de cada passo e guarda a sobra, para um gesto longo dar vários passos.
        let sign: CGFloat = travelled < 0 ? -1 : 1
        travelled -= sign * CGFloat(count) * Self.preciseThreshold
        return sign < 0 ? count : -count
    }

    /// Esquece o que sobrou: um gesto novo começa do zero.
    mutating func reset() {
        travelled = 0
    }
}

/// Troca de mural com um arrasto horizontal de dois dedos, sem atrapalhar os cliques nas capas.
///
/// Usado como `.overlay` da vitrine. É AppKit, e não um `DragGesture`, porque a rolagem anda por um caminho próprio e
/// nunca disputa com o toque das capas. A rolagem vertical passa adiante, intacta.
///
/// Por cima, e não por trás: o SwiftUI entrega a rolagem à vista que o teste de acerto achar, e sobre uma capa (que tem
/// toque) a achada é a do próprio SwiftUI, então uma vista atrás nunca receberia a rolagem ali. Por cima, a vista
/// só se deixa achar pela rolagem (ver ``SwipeView/hitTest(_:)``) e o clique atravessa até a capa.
struct CoverflowSwipe: NSViewRepresentable {
    /// Chamado com os passos do gesto: positivo vai para o mural seguinte; negativo, para o anterior.
    let onStep: (Int) -> Void

    func makeNSView(context: Context) -> SwipeView {
        SwipeView(onStep: onStep)
    }

    func updateNSView(_ nsView: SwipeView, context: Context) {
        nsView.onStep = onStep
    }

    final class SwipeView: NSView {
        var onStep: (Int) -> Void
        /// O tipo do evento que o aplicativo está despachando; troca-se nos testes, que não têm evento de verdade.
        var currentEventType: () -> NSEvent.EventType? = { NSApp.currentEvent?.type }
        private var accumulator = SwipeAccumulator()

        init(onStep: @escaping (Int) -> Void) {
            self.onStep = onStep
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        /// Só a rolagem acha esta vista; o clique e o movimento do ponteiro a atravessam e chegam às capas.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard currentEventType() == .scrollWheel else { return nil }
            return super.hitTest(point)
        }

        override func scrollWheel(with event: NSEvent) {
            // Um gesto novo começa sem a sobra do anterior; e acaba quando os dedos saem, o sistema cancela ou a
            // inércia termina. A inércia (momentum) conta como parte do gesto: um arremesso dá vários passos.
            if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
                accumulator.reset()
            }
            defer {
                if event.phase.contains(.ended) || event.phase.contains(.cancelled) || event.momentumPhase.contains(.ended) {
                    accumulator.reset()
                }
            }

            // O AppKit já entrega o delta no sentido que o usuário escolheu (rolagem natural ou não), e a vitrine o
            // respeita como qualquer conteúdo rolável: nada de desfazer a inversão com `isDirectionInvertedFromDevice`,
            // que serve só a quem precisa ignorar essa escolha.
            let deltaX = event.scrollingDeltaX
            let deltaY = event.scrollingDeltaY
            guard SwipeAccumulator.isHorizontal(deltaX: deltaX, deltaY: deltaY) else {
                super.scrollWheel(with: event)
                return
            }

            let steps = accumulator.add(deltaX: deltaX, deltaY: deltaY, isPrecise: event.hasPreciseScrollingDeltas)
            if steps != 0 {
                onStep(steps)
            }
        }
    }
}
