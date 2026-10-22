import MuralKit
import SwiftUI

/// Background used by control previews to show the glass effect over representative card surfaces.
struct PreviewBackdrop: View {
    /// Uses the item-detail page background instead of the board canvas.
    var page = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                page ? Theme.page : Theme.canvas
                RoundedRectangle(cornerRadius: Theme.cardCorner)
                    .fill(.white)
                    .frame(width: size.width * 0.28, height: size.height * 0.8)
                    .offset(x: size.width * 0.04, y: size.height * 0.1)
                RoundedRectangle(cornerRadius: Theme.cardCorner)
                    .fill(Color(white: 0.2))
                    .frame(width: size.width * 0.24, height: size.height * 0.7)
                    .offset(x: size.width * 0.28, y: size.height * 0.2)
                Rectangle()
                    .fill(Theme.sticky(.orange))
                    .frame(width: size.width * 0.18, height: size.height * 0.5)
                    .offset(x: size.width * 0.5, y: size.height * 0.05)
                RoundedRectangle(cornerRadius: Theme.mediaCorner)
                    .fill(LinearGradient(colors: [.indigo, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: size.width * 0.3, height: size.height * 0.85)
                    .offset(x: size.width * 0.66, y: size.height * 0.08)
            }
        }
    }
}
