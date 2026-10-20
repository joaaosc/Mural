import MuralKit
import SwiftUI

/// Linha marcável da lista, exposta à acessibilidade como alternância.
struct ChecklistRow: View {
    let entry: ChecklistEntry
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: entry.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(entry.isDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                Text(entry.text)
                    .font(.reading)
                    .strikethrough(entry.isDone)
                    .foregroundStyle(entry.isDone ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.text)
        .accessibilityValue(entry.isDone ? "Marcado" : "Não marcado")
        .accessibilityAddTraits(.isToggle)
    }
}
