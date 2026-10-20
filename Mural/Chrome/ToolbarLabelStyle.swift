import SwiftUI

/// Ícone com legenda embaixo, como os itens "ícone e texto" das barras do macOS.
/// Sem legenda, fica só o ícone (a dica e a acessibilidade continuam com o título).
struct ToolbarLabelStyle: LabelStyle {
    var showsTitle: Bool

    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 3) {
            configuration.icon
                .font(.system(size: 15, weight: .medium))
                .frame(height: 18)
            if showsTitle {
                configuration.title
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
        .frame(width: showsTitle ? 56 : 30, height: showsTitle ? 42 : 30)
        .contentShape(.rect)
    }
}
