import MuralKit
import SwiftUI

enum ThumbnailLoadPhase: Equatable {
    case loading
    case loaded
    case failed

    static func result(hasImage: Bool) -> Self { hasImage ? .loaded : .failed }
}

/// Mostra a miniatura de um arquivo de mídia, com um fundo neutro enquanto carrega.
struct ThumbnailView: View {
    let url: URL?
    let kind: ItemKind
    var maxPixelSize = 640
    var contentMode: ContentMode = .fill
    var showsRetry = false

    @State private var image: CGImage?
    @State private var imageRequest: ThumbnailRequest?
    @State private var loadState: ThumbnailLoadPhase = .loading
    @State private var retryAttempt = 0

    private var request: ThumbnailRequest? {
        url.map { ThumbnailRequest(url: $0, kind: kind, maxPixelSize: maxPixelSize) }
    }

    var body: some View {
        let currentRequest = request
        let cached = currentRequest.flatMap { ThumbnailCache.shared.cachedImage(for: $0) }
        let shown = imageRequest == currentRequest ? image : cached
        ZStack {
            if let image = shown {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if imageRequest == currentRequest, loadState == .failed {
                VStack(spacing: 8) {
                    Label("Prévia indisponível", systemImage: "photo")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if showsRetry {
                        Button("Tentar novamente", action: retry)
                            .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary)
                .accessibilityElement(children: .contain)
            } else {
                Rectangle().fill(.quaternary)
                    .accessibilityLabel("Carregando prévia")
            }
        }
        .task(id: ThumbnailTaskID(request: currentRequest, retryAttempt: retryAttempt)) {
            guard !Task.isCancelled, request == currentRequest else { return }
            image = nil
            imageRequest = currentRequest
            loadState = currentRequest == nil ? .failed : .loading
            guard let currentRequest, !Task.isCancelled else { return }

            let loadedImage = await ThumbnailCache.shared.image(for: currentRequest)
            guard !Task.isCancelled, request == currentRequest else { return }

            image = loadedImage
            imageRequest = currentRequest
            loadState = .result(hasImage: loadedImage != nil)
        }
    }

    private func retry() {
        guard request != nil else { return }
        retryAttempt &+= 1
    }
}

private struct ThumbnailTaskID: Equatable {
    let request: ThumbnailRequest?
    let retryAttempt: Int
}
