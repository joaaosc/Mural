import AppKit
import SwiftUI

extension View {
    /// Shift + arrastar numa área vazia desenha um retângulo e marca os cartões que ele cruza, somados ao que
    /// já estava marcado. Sem Shift no começo, o arrasto é ignorado; começado em cima de um cartão, o arrasto
    /// continua sendo do cartão (o gesto fica atrás dele).
    /// - Parameters:
    ///   - space: espaço de coordenadas em que `frames` são medidos; o modificador precisa ficar dentro dele.
    ///   - selection: `nil` desliga o retângulo (nível coberto, prévia de pasta).
    ///   - lineWidth: espessura do contorno; no mural com zoom, `1 / zoom` para ficar com um ponto na tela.
    ///   - isActive: avisa enquanto o retângulo existe (o mural não abre a prévia de pasta nesse tempo).
    ///   - frames: quadro de cada cartão do nível, lido a cada movimento.
    func marqueeSelecting(
        in space: String,
        selection: CardSelection?,
        lineWidth: CGFloat = 1,
        isActive: Binding<Bool> = .constant(false),
        frames: @escaping () -> [UUID: CGRect]
    ) -> some View {
        modifier(
            MarqueeSelecting(
                space: space, selection: selection, lineWidth: lineWidth, isActive: isActive, frames: frames))
    }
}

private struct MarqueeSelecting: ViewModifier {
    let space: String
    let selection: CardSelection?
    let lineWidth: CGFloat
    @Binding var isActive: Bool
    let frames: () -> [UUID: CGRect]

    @State private var marquee: MarqueeSelection?
    /// O arrasto começou sem Shift: fica ignorado até o botão ser solto.
    @State private var ignoresDrag = false
    /// Shift segurado agora, pelas teclas que a janela recebe (vale também para eventos simulados).
    @State private var isShiftHeld = false
    /// Volta sozinho a falso, inclusive quando o gesto é cancelado sem `onEnded`.
    @GestureState private var isDragging = false

    func body(content: Content) -> some View {
        content
            .background {
                Color.clear
                    .contentShape(.rect)
                    .gesture(gesture, isEnabled: selection != nil)
            }
            .overlay(alignment: .topLeading) {
                if let rect = marquee?.rect {
                    Rectangle()
                        .fill(.tint.opacity(0.12))
                        .stroke(.tint, lineWidth: lineWidth)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onChange(of: isDragging) { _, dragging in
                if !dragging { finish() }
            }
            .onModifierKeysChanged(mask: .shift, initial: true) { _, keys in
                isShiftHeld = keys.contains(.shift)
            }
    }

    private var gesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(space))
            .updating($isDragging) { _, dragging, _ in dragging = true }
            .onChanged(update)
            .onEnded { _ in finish() }
    }

    private func update(_ value: DragGesture.Value) {
        guard let selection, !ignoresDrag else { return }
        if marquee == nil {
            // O Shift vale no começo do arrasto, como o ⌘ no clique do cartão.
            guard isShiftHeld || NSEvent.modifierFlags.contains(.shift) else {
                ignoresDrag = true
                return
            }
            marquee = MarqueeSelection(start: value.startLocation, base: selection.selected)
            isActive = true
        }
        marquee?.current = value.location
        if let marquee {
            selection.select(marquee.selection(in: frames()))
        }
    }

    private func finish() {
        marquee = nil
        ignoresDrag = false
        if isActive { isActive = false }
    }
}
