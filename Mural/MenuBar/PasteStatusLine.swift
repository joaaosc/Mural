import SwiftUI

/// A linha de estado do colar do painel: nada em repouso; "Colando…", a frase do editor que abre ou da edição que é lida,
/// "Colado em …" ou o motivo da falha nos outros casos.
struct PasteStatusLine: View {
    let status: PasteStatus

    var body: some View {
        switch status {
        case .idle:
            EmptyView()
        case .pasting:
            row("Colando…") { ProgressView().controlSize(.small) }
        case .working(let message):
            row(message) { ProgressView().controlSize(.small) }
        case .pasted(let message):
            row(message) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
        case .failed(let message):
            row(message) { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
        }
    }

    private func row<Icon: View>(_ message: String, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 6) {
            icon()
                .frame(width: 16, height: 16)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("menu-bar-paste-status")
    }
}
