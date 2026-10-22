import SwiftUI

/// Botão sem borda da barra, com a área de clique no espaço todo do rótulo.
struct CreationBarButtonStyle: ButtonStyle {
    /// Folga dos lados; os botões só com ícone da barra do seletor usam menos.
    var horizontalPadding: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 7)
            .contentShape(.capsule)
            .background(.primary.opacity(configuration.isPressed ? 0.12 : 0), in: .capsule)
    }
}
