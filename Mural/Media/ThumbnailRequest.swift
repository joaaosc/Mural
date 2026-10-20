import Foundation
import MuralKit

/// Identidade completa de uma miniatura em cache ou em geração.
struct ThumbnailRequest: Hashable, Sendable {
    let url: URL
    let kind: ItemKind
    let maxPixelSize: Int
}
