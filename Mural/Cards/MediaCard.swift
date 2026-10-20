import MuralKit
import SwiftUI

/// Foto, vídeo ou PDF: a miniatura recortada com cantos arredondados.
struct MediaCard: View {
    let url: URL?
    let kind: ItemKind

    var body: some View {
        // O Color.clear define o tamanho; a miniatura preenche e é recortada.
        Color.clear
            .overlay { ThumbnailView(url: url, kind: kind) }
            .overlay {
                if kind == .video {
                    Image(systemName: "play.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                }
            }
            .background(kind == .pdf ? Theme.paper : .clear)
            .clipShape(.rect(cornerRadius: kind == .pdf ? Theme.cardCorner : Theme.mediaCorner))
            .cardShadow()
    }
}
