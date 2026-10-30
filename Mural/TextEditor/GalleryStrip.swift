import CoreGraphics
import MuralKit
import SwiftUI

/// A tira de miniaturas dos murais, rolando na horizontal; a escolhida fica à vista (a tira rola até ela ao mudar).
struct GalleryStrip: View {
    let entries: [BoardLibraryEntry]
    let selection: Int
    let covers: [BoardID: CGImage]
    let select: @MainActor (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(entries.enumerated(), id: \.element.manifest.id) { index, entry in
                        GalleryThumbnail(
                            entry: entry, cover: covers[entry.manifest.id], isSelected: index == selection,
                            action: { select(index) }
                        )
                        .id(entry.manifest.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection, initial: true) {
                guard entries.indices.contains(selection) else { return }
                withAnimation { proxy.scrollTo(entries[selection].manifest.id, anchor: .center) }
            }
        }
        .frame(height: GalleryThumbnail.size.height + 12)
        .accessibilityIdentifier("paste-destination-strip")
    }
}
