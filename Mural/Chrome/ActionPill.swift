import SwiftUI

/// Pílula flutuante com as ações do item aberto (editar, copiar, abrir, apagar).
///
/// Vidro estático por trás de botões sem borda; tamanho e área de clique ficam dentro
/// do rótulo de cada botão, para o clique valer em todo o espaço visível.
struct ActionPill: View {
    let actions: [PillAction]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(actions) { action in
                Button(role: action.role, action: action.perform) {
                    Label(action.title, systemImage: action.symbol)
                        .labelStyle(.iconOnly)
                        .frame(width: 34, height: 30)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(action.role == .destructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                .keyboardShortcut(action.shortcut)
                .help(action.title)
            }
        }
        .font(.body.weight(.medium))
        .padding(.horizontal, 6)
        .glassEffect(.regular, in: .capsule)
    }
}

#Preview {
    ActionPill(actions: [
        PillAction(title: "Copiar", symbol: "square.on.square") {},
        PillAction(title: "Abrir no app padrão", symbol: "arrow.up.forward.app") {},
        PillAction(title: "Apagar", symbol: "trash", role: .destructive) {},
    ])
    .padding(40)
    .background(Theme.page)
}
