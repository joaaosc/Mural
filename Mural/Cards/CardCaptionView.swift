import SwiftUI

/// Legenda independente do nome do cartão, usada em qualquer cartão que tenha
/// uma legenda persistida. Mantém a edição e a apresentação separadas do corpo.
struct CardCaptionView: View {
    let caption: String?

    var body: some View {
        if let caption, !caption.isEmpty {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: .rect(cornerRadius: 4))
                .padding(5)
                .allowsHitTesting(false)
        }
    }
}
