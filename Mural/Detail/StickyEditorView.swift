import MuralKit
import SwiftUI

/// Post-it ampliado em edição: o texto no próprio papel colorido e as cinco
/// cores embaixo. Post-it não usa Markdown nem dobra.
struct StickyEditorView: View {
    let itemID: UUID
    let session: BoardWindowSession

    @State private var draft: NoteDraft
    @FocusState private var isFocused: Bool

    init(itemID: UUID, session: BoardWindowSession) {
        self.itemID = itemID
        self.session = session
        _draft = State(initialValue: session.noteDraft(for: itemID))
    }

    var body: some View {
        VStack(spacing: 22) {
            TextEditor(text: $draft.text)
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(Theme.stickyInk)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .padding(30)
                .frame(width: 420, height: 420)
                .background(Theme.sticky(draft.color), in: .rect(cornerRadius: 6))
                .cardShadow()
                .accessibilityLabel("Texto do post-it")
            StickyColorPicker(selection: $draft.color)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: draft) { _, newDraft in
            session.setNoteDraft(newDraft, for: itemID)
        }
        .onKeyPress(.escape) {
            session.finishEditing()
            return .handled
        }
        .onAppear(perform: focus)
    }

    private func focus() {
        isFocused = true
    }
}
