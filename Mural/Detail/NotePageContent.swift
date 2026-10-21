import MuralKit
import StretchTextUI
import SwiftUI

/// Título e corpo da nota na página de leitura, com o corpo em Markdown dobrado.
///
/// Fica numa view própria para que a dobra só seja refeita quando o cartão
/// muda, e não a cada passo da rolagem da página.
struct NotePageContent: View {
    let item: BoardItem
    let session: BoardWindowSession?

    var body: some View {
        let result = NoteFolding.fold(for: item)
        VStack(alignment: .leading, spacing: 18) {
            Text(item.title)
                .font(.system(size: 40, weight: .bold))
                .textSelection(.enabled)
            if let result {
                FoldedTextView(itemID: item.id, result: result, session: session)
                    .stretchMarkdownStyle(.notePage)
                    .lineSpacing(5)
                FoldStatusLine(itemID: item.id, result: result, session: session)
                    .padding(.top, 8)
            }
        }
        .task(id: item.id) {
            session?.prioritizeKeySentences(for: item.id)
        }
    }
}
