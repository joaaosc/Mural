import SwiftUI

/// Pílula escura flutuante com as ações do item aberto (copiar, abrir, apagar).
struct ActionPill: View {
    let actions: [PillAction]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(actions) { action in
                Button(action.title, systemImage: action.symbol, role: action.role, action: action.perform)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .frame(width: 34, height: 30)
                    .contentShape(.rect)
                    .help(action.title)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .glassEffect(.regular.tint(.black.opacity(0.72)).interactive(), in: .capsule)
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
