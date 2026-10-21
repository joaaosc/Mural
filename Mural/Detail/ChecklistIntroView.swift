import MuralKit
import StretchTextUI
import SwiftUI

/// Texto de abertura da lista, dobrado pelo StretchText como o corpo das notas.
struct ChecklistIntroView: View {
    let item: BoardItem
    let session: BoardWindowSession?

    var body: some View {
        if let result = NoteFolding.fold(for: item) {
            FoldedTextView(itemID: item.id, result: result, session: session)
                .stretchMarkdownStyle(.checklistIntro)
                .task(id: item.id) {
                    session?.prioritizeKeySentences(for: item.id)
                }
        }
    }
}
