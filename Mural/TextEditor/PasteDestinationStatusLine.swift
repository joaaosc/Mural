import SwiftUI

/// A linha de estado da galeria: nada em repouso; "Colando…", "Colado em …" ou o motivo da falha nos outros casos.
struct PasteDestinationStatusLine: View {
    let status: PasteStatus
    /// Um aviso de um colar que deu certo (uma imagem perdida).
    var warning: String?

    var body: some View {
        HStack(spacing: 6) {
            switch status {
            case .idle:
                EmptyView()
            case .pasting:
                ProgressView().controlSize(.small)
                Text("Colando…")
            case .pasted(let message):
                Image(systemName: warning == nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(warning == nil ? .green : .orange)
                Text(warning.map { "\(message). \($0)" } ?? message)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message)
            }
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(minHeight: 20)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("paste-destination-status")
    }
}
