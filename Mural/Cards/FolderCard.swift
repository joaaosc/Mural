import MuralKit
import SwiftUI

/// Pasta: duas folhas empilhadas com etiqueta e título; a primeira mídia de dentro
/// aparece espiando pela borda direita, como no conceito.
struct FolderCard: View {
    let folder: BoardItem
    let itemCount: Int
    /// Arquivo da primeira imagem ou vídeo dentro da pasta, se houver.
    let peekURL: URL?
    let peekKind: ItemKind?

    var body: some View {
        ZStack {
            if let peekURL, let peekKind {
                ThumbnailView(url: peekURL, kind: peekKind, maxPixelSize: 320)
                    .frame(width: 70, height: 120)
                    .clipShape(.rect(cornerRadius: 10))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(x: 14)
            }
            RoundedRectangle(cornerRadius: Theme.cardCorner)
                .fill(Theme.paperBack)
                .offset(x: 6)
                .cardShadow()
            front
        }
    }

    private var front: some View {
        VStack(alignment: .leading, spacing: 2) {
            Capsule()
                .fill(.quaternary)
                .frame(width: 28, height: 8)
            Spacer(minLength: 0)
            Text(folder.tag ?? "Pasta")
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(.secondary)
            Text(folder.title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(2)
            Text(itemCount == 1 ? "1 item" : "\(itemCount) itens")
                .font(.system(size: 6))
                .foregroundStyle(.tertiary)
        }
        .paperSheet()
    }
}
