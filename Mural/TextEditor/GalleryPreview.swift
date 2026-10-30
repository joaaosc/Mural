import CoreGraphics
import MuralKit
import SwiftUI

/// A prévia grande do mural escolhido: a capa, no tamanho que couber, e o nome embaixo. Sem capa, um quadro com o símbolo.
struct GalleryPreview: View {
    let entry: BoardLibraryEntry?
    let cover: CGImage?

    var body: some View {
        VStack(spacing: 10) {
            Group {
                if let cover {
                    Image(decorative: cover, scale: 1)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: Theme.cardCorner))
            .clipShape(.rect(cornerRadius: Theme.cardCorner))
            .accessibilityHidden(true)

            Text(entry?.manifest.name ?? "")
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .accessibilityIdentifier("paste-destination-board-name")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(entry.map { "Mural \($0.manifest.name)" } ?? "Nenhum mural")
        .accessibilityIdentifier("paste-destination-preview")
    }
}
