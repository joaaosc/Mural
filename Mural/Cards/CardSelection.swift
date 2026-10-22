import SwiftUI

/// O que um cartão precisa para participar do seletor de ⌘: se o seletor está aberto,
/// o que está marcado e como marcar.
struct CardSelection {
    var isActive: Bool
    var selected: Set<UUID>
    var toggle: @MainActor (UUID) -> Void
    /// Troca a marcação inteira (o retângulo de Shift + arrastar).
    var select: @MainActor (Set<UUID>) -> Void = { _ in }
}

extension CardSelection {
    /// Seleção do nível aberto na janela.
    @MainActor
    init(session: BoardWindowSession) {
        self.init(
            isActive: session.isSelecting, selected: session.currentSelection, toggle: session.toggleSelection,
            select: session.select)
    }
}

/// Marca de seleção sobre o canto do cartão: círculo vazio com o seletor aberto, preenchido
/// com a cor de destaque do sistema quando o cartão está marcado. Pequena e sólida, e não de vidro:
/// dezenas de vidros dentro do mural com zoom pesavam e refletiam a cor do cartão de baixo.
struct SelectionBadge: View {
    let isSelected: Bool

    static let size: CGFloat = 18
    /// Quanto a marca sai para fora do canto do cartão, para não cobrir o título.
    static let outset: CGFloat = 6

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: Self.size - 2))
            .symbolRenderingMode(.palette)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary), AnyShapeStyle(.tint))
            .contentTransition(.symbolEffect(.replace))
            .frame(width: Self.size, height: Self.size)
            .background(Theme.paper, in: .circle)
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
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
