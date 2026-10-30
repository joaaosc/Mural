import MuralKit
import StretchText
import StretchTextUI
import SwiftUI

/// Título e corpo da nota na página de leitura, com o corpo em Markdown dobrado.
///
/// Fica numa view própria para que a dobra só seja refeita quando o cartão
/// muda, e não a cada passo da rolagem da página.
struct NotePageContent: View {
    let item: BoardItem
    let model: BoardModel?
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
                    .modifier(NoteTaskToggle(itemID: item.id, source: result.segmentation.source, session: session))
                    .stretchMarkdownImage {
                        NoteImageView(image: $0, item: item, model: model, maxPixelSize: 1600, session: session)
                    }
                FoldStatusLine(itemID: item.id, result: result, session: session)
                    .padding(.top, 8)
            }
        }
        .task(id: item.id) {
            session?.prioritizeKeySentences(for: item.id)
        }
    }
}

/// Faz a tarefa da nota virar botão na página; sem sessão (prévias), ela fica só desenho.
private struct NoteTaskToggle: ViewModifier {
    let itemID: UUID
    let source: String
    let session: BoardWindowSession?

    func body(content: Content) -> some View {
        if let session {
            content.stretchMarkdownTaskToggle { segment in
                session.toggleNoteTask(itemID, segment: segment, source: source)
            }
        } else {
            content
        }
    }
}
