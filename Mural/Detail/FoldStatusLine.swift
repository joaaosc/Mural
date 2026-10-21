import MuralKit
import StretchText
import SwiftUI

/// Linha discreta no fim do texto: o modelo escolhendo as frases curtas, ou por
/// que elas ficaram pela primeira frase.
struct FoldStatusLine: View {
    let itemID: UUID
    let result: FoldResult
    let session: BoardWindowSession?

    var body: some View {
        if session?.keySentences?.currentItemID == itemID {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Escolhendo as frases curtas…")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        } else if let notice = NoteFolding.notice(for: result) {
            Text(notice)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
