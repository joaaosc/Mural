import MuralKit
import SwiftUI

/// Edição da nota na própria página: título num campo e corpo em Markdown, em
/// fonte monoespaçada. ⌘B e ⌘I (menu Formatar) aplicam negrito e itálico na seleção.
///
/// O texto vai para o rascunho da sessão a cada mudança e só entra no mural ao
/// concluir, ao sair da página ou ao fechar a janela.
struct NoteEditorView: View {
    let itemID: UUID
    let session: BoardWindowSession

    @State private var draft: NoteDraft
    @State private var selection: TextSelection?
    @FocusState private var focusedField: NoteEditorField?

    init(itemID: UUID, session: BoardWindowSession) {
        self.itemID = itemID
        self.session = session
        _draft = State(initialValue: session.noteDraft(for: itemID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Título", text: $draft.title)
                .textFieldStyle(.plain)
                .font(.system(size: 40, weight: .bold))
                .focused($focusedField, equals: .title)
                .onSubmit(focusBody)
            TextEditor(text: $draft.text, selection: $selection)
                .font(.system(.body, design: .monospaced))
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .focused($focusedField, equals: .body)
                .focusedValue(\.markdownFormatting, MarkdownFormattingAction(apply: toggle))
                .accessibilityLabel("Texto da nota em Markdown")
            Text("Markdown: # título, - lista, - [ ] tarefa, > citação, **negrito**, *itálico*.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onChange(of: draft) { _, newDraft in
            session.setNoteDraft(newDraft, for: itemID)
        }
        .onKeyPress(.escape) {
            session.finishEditing()
            return .handled
        }
        .onAppear(perform: focusFirstField)
    }

    /// Nota nova começa pelo título; nota existente, pelo fim do corpo.
    private func focusFirstField() {
        focusedField = draft.title.isEmpty && draft.text.isEmpty ? .title : .body
    }

    private func focusBody() {
        focusedField = .body
    }

    private func toggle(_ emphasis: MarkdownEmphasis) {
        let text = draft.text
        let result = emphasis.toggle(in: text, selection: selectedOffsets(in: text))
        draft.text = result.text
        let start = result.text.index(result.text.startIndex, offsetBy: result.selection.lowerBound)
        let end = result.text.index(result.text.startIndex, offsetBy: result.selection.upperBound)
        selection = TextSelection(range: start..<end)
    }

    /// A seleção atual em posições de `Character`; sem seleção, o fim do texto.
    private func selectedOffsets(in text: String) -> Range<Int> {
        let count = text.count
        guard case .selection(let range) = selection?.indices,
            range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex
        else { return count..<count }
        let lower = text.distance(from: text.startIndex, to: range.lowerBound)
        let upper = text.distance(from: text.startIndex, to: range.upperBound)
        return lower..<upper
    }
}
