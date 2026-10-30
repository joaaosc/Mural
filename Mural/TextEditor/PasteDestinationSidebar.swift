import MuralKit
import SwiftUI

/// O lado direito da galeria: "Colar como", a linha de estado e os botões Cancelar e Colar.
struct PasteDestinationSidebar: View {
    let model: PasteDestinationModel
    /// Pede para colar com o jeito escolhido.
    let requestPaste: @MainActor () -> Void
    let close: @MainActor () -> Void

    static let width: CGFloat = 280

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PasteKindList(
                suggestion: model.suggestion, selectedKind: model.selectedKind,
                boardName: model.selectedEntry?.manifest.name ?? "",
                choose: { kind in
                    model.selectKind(kind)
                    requestPaste()
                })
            Spacer(minLength: 0)
            PasteDestinationStatusLine(status: model.status, warning: model.warning)
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel, action: close)
                    .keyboardShortcut(.cancelAction)
                    .focusable(false)
                    .accessibilityIdentifier("paste-destination-cancel")
                Button("Colar", action: requestPaste)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canPaste)
                    .focusable(false)
                    .accessibilityIdentifier("paste-destination-paste")
            }
        }
        .padding(16)
        .frame(width: Self.width)
    }
}
