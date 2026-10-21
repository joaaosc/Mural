import SwiftUI

/// Botão sem borda da barra, com a área de clique no espaço todo do rótulo.
struct CreationBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(.capsule)
            .background(.primary.opacity(configuration.isPressed ? 0.12 : 0), in: .capsule)
    }
}
