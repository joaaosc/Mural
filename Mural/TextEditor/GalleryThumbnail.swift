import CoreGraphics
import MuralKit
import SwiftUI

/// A miniatura de um mural na tira da galeria: 96 × 60 pt, com a borda de 2 pt na cor de destaque quando escolhido.
struct GalleryThumbnail: View {
    let entry: BoardLibraryEntry
    let cover: CGImage?
    let isSelected: Bool
    let action: @MainActor () -> Void

    static let size = CGSize(width: 96, height: 60)

    var body: some View {
        Button(action: action) {
            Group {
                if let cover {
                    Image(decorative: cover, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "rectangle.on.rectangle").foregroundStyle(.tertiary)
                }
            }
            .frame(width: Self.size.width, height: Self.size.height)
            .background(.quaternary.opacity(0.4))
            .clipShape(.rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0)
            }
            .contentShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(entry.manifest.name)
        .accessibilityLabel(entry.manifest.name)
        .accessibilityHint("Escolhe este mural para receber o texto.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("paste-destination-thumbnail")
    }
}
