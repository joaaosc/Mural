import MuralKit
import SwiftUI

/// Mostra a miniatura de um arquivo de mídia, com um fundo neutro enquanto carrega.
struct ThumbnailView: View {
    let url: URL?
    let kind: ItemKind
    var maxPixelSize = 640
    var contentMode: ContentMode = .fill

    @State private var image: CGImage?
    @State private var imageRequest: ThumbnailRequest?
    @State private var activeRequest: ThumbnailRequest?

    private var request: ThumbnailRequest? {
        url.map { ThumbnailRequest(url: $0, kind: kind, maxPixelSize: maxPixelSize) }
    }

    var body: some View {
        let shown =
            imageRequest == request
            ? image
            : request.flatMap { ThumbnailCache.shared.cachedImage(for: $0) }
        ZStack {
            if let image = shown {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .task(id: request) {
            activeRequest = request
            image = nil
            imageRequest = nil
            guard let request, !Task.isCancelled else { return }

            let loadedImage = await ThumbnailCache.shared.image(for: request)
            guard !Task.isCancelled, activeRequest == request else { return }

            image = loadedImage
            imageRequest = loadedImage == nil ? nil : request
        }
    }
}
