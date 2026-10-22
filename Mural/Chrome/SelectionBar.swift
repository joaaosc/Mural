import SwiftUI

/// Barra do seletor, no lugar da barra de criação enquanto a seleção está aberta: quantos
/// cartões estão marcados, Apagar… e Cancelar. Mesmo vidro e botões da barra de criação.
struct SelectionBar: View {
    let count: Int
    var onDelete: () -> Void
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Text(title)
                .font(.body.weight(.medium))
                .monospacedDigit()
                .contentTransition(.numericText())
                .padding(.horizontal, 12)
            Button("Apagar…", systemImage: "trash", role: .destructive, action: onDelete)
                .foregroundStyle(count == 0 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.red))
                .disabled(count == 0)
                .help("Apagar os cartões marcados (⌫)")
            Button("Cancelar", systemImage: "xmark", action: onCancel)
                .help("Desmarcar tudo (Esc)")
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(CreationBarButtonStyle())
        .padding(4)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("selection-bar")
    }

    private var title: String {
        switch count {
        case 0: "Clique nos cartões para marcar"
        case 1: "1 selecionado"
        default: "\(count) selecionados"
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        SelectionBar(count: 0, onDelete: {}, onCancel: {})
        SelectionBar(count: 3, onDelete: {}, onCancel: {})
    }
    .padding(40)
    .background(Theme.canvas)
}
