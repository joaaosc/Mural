import MuralKit
import SwiftUI

/// Folha que pede o endereço de um link para pôr no texto. Aceita um endereço por linha; "Inserir" só vale quando todas as linhas são
/// endereços da web (`WebLink.urls(inText:)`).
struct LinkInsertSheet: View {
    /// Recebe os endereços, na ordem.
    let onInsert: ([URL]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @FocusState private var fieldHasFocus: Bool

    private var urls: [URL] { WebLink.urls(inText: address) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Inserir link").font(.headline)
            TextField("https://exemplo.com", text: $address)
                .textFieldStyle(.roundedBorder)
                .focused($fieldHasFocus)
                .onSubmit(insert)
                .accessibilityIdentifier("link-insert-field")
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Inserir", action: insert)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(urls.isEmpty)
                    .accessibilityIdentifier("link-insert-confirm")
            }
        }
        .padding(24)
        .frame(width: 360)
        .defaultFocus($fieldHasFocus, true)
        .onAppear { fieldHasFocus = true }
    }

    private func insert() {
        let urls = urls
        guard !urls.isEmpty else { return }
        onInsert(urls)
        dismiss()
    }
}

#if DEBUG
#Preview("Inserir link, claro", traits: .sizeThatFitsLayout) {
    LinkInsertSheet(onInsert: { _ in }).preferredColorScheme(.light)
}

#Preview("Inserir link, escuro", traits: .sizeThatFitsLayout) {
    LinkInsertSheet(onInsert: { _ in }).preferredColorScheme(.dark)
}
#endif
