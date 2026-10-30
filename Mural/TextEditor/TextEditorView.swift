import MuralKit
import SwiftUI

/// O conteúdo da janela do editor de texto: o campo de texto, a barra de ferramentas e a escolha de lembretes.
///
/// Fechar a janela com texto pergunta antes (`dismissalConfirmationDialog`, que vale para o botão de fechar, ⌘W e o fechamento
/// por código): "Descartar" limpa o documento e fecha, e o texto não fica guardado entre aberturas. Com o documento vazio,
/// fecha direto. Esc não faz nada.
struct TextEditorView: View {
    let session: TextEditorSession

    @State private var isPickingReminders = false

    var body: some View {
        let document = session.document
        TextEditorBody(document: document)
            .frame(minWidth: 640, idealWidth: 720, maxWidth: .infinity, minHeight: 320, idealHeight: 520, maxHeight: .infinity)
            .toolbar {
                TextEditorToolbar(actions: actions, wordCount: document.wordCount)
            }
            .navigationTitle("Editor de texto")
            .toolbar(removing: .title)
            .sheet(isPresented: $isPickingReminders) {
                ReminderPickerSheet(provider: RemindersCenter.shared) { snapshots in
                    document.insertCards(snapshots.map { .reminder($0) })
                }
            }
            .dismissalConfirmationDialog("Descartar o texto?", shouldPresent: !document.isEmpty) {
                Button("Descartar", role: .destructive) { document.clear() }
            }
            // Com a folha de lembretes aberta os comandos de menu do editor ficam desligados.
            .focusedSceneValue(\.textEditorActions, isPickingReminders ? nil : actions)
            .focusedSceneValue(\.markdownFormatting, MarkdownFormattingAction(apply: document.applyEmphasis))
            .onAppear { session.isOpen = true }
            .onDisappear { session.isOpen = false }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(TextEditorWindow.accessibilityIdentifier)
    }

    private var actions: TextEditorActions {
        let document = session.document
        return TextEditorActions(
            applyFormat: { document.applyFormat($0) },
            applyEmphasis: { document.applyEmphasis($0) },
            insertReminder: { isPickingReminders = true },
            requestPaste: { session.onPasteRequested?() },
            canPaste: session.canRequestPaste)
    }
}

#if DEBUG
private struct TextEditorViewSample: View {
    @State private var session: TextEditorSession = {
        let session = TextEditorSession()
        session.document.text = "Visita à obra: medir a parede norte.\n\nPendências:\n- Reboco\n- Pintura"
        return session
    }()

    var body: some View {
        TextEditorView(session: session)
            .frame(width: 720, height: 520)
    }
}

#Preview("Editor de texto, claro") {
    TextEditorViewSample().preferredColorScheme(.light)
}

#Preview("Editor de texto, escuro") {
    TextEditorViewSample().preferredColorScheme(.dark)
}
#endif
