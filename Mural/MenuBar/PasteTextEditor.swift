import SwiftUI

/// O editor de texto do painel ("Editar antes de colar"): o texto copiado num campo de edição, já com o foco, e embaixo
/// os botões de voltar e de colar.
///
/// O botão de colar leva o nome da maneira de colar que o classificador sugere para o texto de agora (`pasteTitle`) e
/// responde ao ⌘↩; o Esc, tratado pelo painel, volta às maneiras de colar com a edição mantida. Só desenha: quem decide o
/// que fazer com o texto é o modelo do painel.
struct PasteTextEditor: View {
    @Binding var text: String
    /// O nome do mural que recebe o texto, para o cabeçalho.
    let boardName: String
    /// O título do botão de colar ("Colar como Sticker", "Colar como Lista"…).
    let pasteTitle: String
    /// Cola o texto editado.
    let paste: @MainActor () -> Void
    /// Volta às maneiras de colar, mantendo a edição.
    let goBack: @MainActor () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Editar antes de colar")
                    .fontWeight(.medium)
                Spacer(minLength: 12)
                Text("em \(boardName)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.subheadline)
            .padding(.horizontal, 10)

            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .padding(6)
                .frame(height: 120)
                .background(.primary.opacity(0.06), in: .rect(cornerRadius: 8))
                .accessibilityLabel("Texto a colar")
                .accessibilityIdentifier("menu-bar-paste-editor")

            HStack(spacing: 10) {
                Button("Voltar", systemImage: "chevron.backward", action: goBack)
                    .buttonStyle(.borderless)
                    .help("Voltar às maneiras de colar, mantendo a edição (Esc)")
                    .accessibilityHint("Volta às maneiras de colar, mantendo o texto editado.")
                    .accessibilityIdentifier("menu-bar-paste-editor-back")
                KeyHint(symbol: "escape", label: "Esc", description: "Esc volta às maneiras de colar")

                Spacer(minLength: 12)

                KeyHint(symbol: "command", label: "↩", description: "Comando Return cola o texto editado")
                Button(pasteTitle, action: paste)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .help("\(pasteTitle) em \(boardName) (⌘↩)")
                    .accessibilityHint("Cola o texto editado no mural do centro da vitrine.")
                    .accessibilityIdentifier("menu-bar-paste-editor-paste")
            }
            .padding(.horizontal, 10)
        }
        .onAppear { isFocused = true }
    }
}

#Preview("Editor de texto", traits: .fixedLayout(width: PanelMetrics.panelWidth, height: 230)) {
    @Previewable @State var text = "Comprar pão\n- leite\n- ovos"
    PasteTextEditor(
        text: $text, boardName: "Compras", pasteTitle: PasteDescription.editorPasteTitle(for: text), paste: {},
        goBack: {}
    )
    .padding()
}
