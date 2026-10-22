import SwiftUI

/// O que um cartão precisa para participar do seletor de ⌘: se o seletor está aberto,
/// o que está marcado e como marcar.
struct CardSelection {
    var isActive: Bool
    var selected: Set<UUID>
    var toggle: @MainActor (UUID) -> Void
}

extension CardSelection {
    /// Seleção do nível aberto na janela.
    @MainActor
    init(session: BoardWindowSession) {
        self.init(isActive: session.isSelecting, selected: session.currentSelection, toggle: session.toggleSelection)
    }
}

/// Marca de seleção no canto do cartão: círculo vazio com o seletor aberto, preenchido
/// com a cor de destaque do sistema quando o cartão está marcado.
struct SelectionBadge: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .symbolRenderingMode(.palette)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary), AnyShapeStyle(.tint))
            .contentTransition(.symbolEffect(.replace))
            .padding(2)
            .glassEffect(.regular, in: .circle)
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 20) {
        SelectionBadge(isSelected: false)
        SelectionBadge(isSelected: true)
    }
    .padding(40)
    .background(Theme.canvas)
}
