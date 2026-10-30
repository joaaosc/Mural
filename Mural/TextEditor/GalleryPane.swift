import CoreGraphics
import MuralKit
import SwiftUI

/// O lado esquerdo da galeria, como a vista Galeria do Finder: a prévia grande do mural escolhido e, embaixo, a tira de miniaturas.
struct GalleryPane: View {
    let entries: [BoardLibraryEntry]
    let selection: Int
    let covers: [BoardID: CGImage]
    let select: @MainActor (Int) -> Void

    var body: some View {
        VStack(spacing: 8) {
            GalleryPreview(
                entry: entries.indices.contains(selection) ? entries[selection] : nil,
                cover: entries.indices.contains(selection) ? covers[entries[selection].manifest.id] : nil
            )
            .padding([.top, .horizontal], 16)
            GalleryStrip(entries: entries, selection: selection, covers: covers, select: select)
        }
        .padding(.bottom, 8)
    }
}
