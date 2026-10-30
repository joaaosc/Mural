import SwiftUI

/// A folha que pede o título antes de colar um Card de texto: começa com o título tirado do texto, Return cola e Esc volta à galeria
/// sem colar. Vazio, o cartão fica com o título tirado do texto.
struct PasteTitleSheet: View {
    @Binding var title: String
    let boardName: String
    let cancel: () -> Void
    let confirm: () -> Void

    @FocusState private var fieldHasFocus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Título do Card de texto").font(.headline)
                Text("Vai para o mural \(boardName).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            TextField("Título", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($fieldHasFocus)
                .onSubmit(confirm)
                .accessibilityIdentifier("paste-title-field")
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("paste-title-cancel")
                Button("Colar", action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("paste-title-confirm")
            }
        }
        .padding(24)
        .frame(width: 360)
        .defaultFocus($fieldHasFocus, true)
        .onAppear { fieldHasFocus = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paste-title-sheet")
    }
}

#if DEBUG
private struct PasteTitleSheetSample: View {
    @State private var title = "Visita à obra"

    var body: some View {
        PasteTitleSheet(title: $title, boardName: "Obra", cancel: {}, confirm: {})
    }
}

#Preview("Título, claro", traits: .sizeThatFitsLayout) {
    PasteTitleSheetSample().preferredColorScheme(.light)
}

#Preview("Título, escuro", traits: .sizeThatFitsLayout) {
    PasteTitleSheetSample().preferredColorScheme(.dark)
}
#endif
