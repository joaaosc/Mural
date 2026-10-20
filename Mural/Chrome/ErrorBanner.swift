import SwiftUI

/// Aviso flutuante no topo da janela, com botão para fechar.
struct ErrorBanner: View {
    let message: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .lineLimit(2)
            Button(action: onDismiss) {
                Label("Fechar", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .frame(width: 24, height: 24)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .help("Fechar aviso")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: 520)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}
