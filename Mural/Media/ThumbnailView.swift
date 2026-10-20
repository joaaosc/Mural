import MuralKit
import SwiftUI

/// Mostra a miniatura de um arquivo de mídia, com um fundo neutro enquanto carrega.
struct ThumbnailView: View {
    let url: URL?
    let kind: ItemKind
    var maxPixelSize = 640
    var contentMode: ContentMode = .fill

    @State private var image: CGImage?

    var body: some View {
        let shown = image ?? url.flatMap { ThumbnailCache.shared.cachedImage(for: $0, maxPixelSize: maxPixelSize) }
        ZStack {
            if let image = shown {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .task(id: url) {
            guard let url else { return }
            image = await ThumbnailCache.shared.image(for: url, kind: kind, maxPixelSize: maxPixelSize)
        }
    }
}
