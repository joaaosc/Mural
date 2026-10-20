import SwiftUI

/// Documento PDF com rolagem contínua e ajuste automático de tamanho.
struct PDFDetailView: View {
    let itemID: UUID
    let url: URL?
    let session: BoardWindowSession?

    var body: some View {
        Group {
            if let url {
                PDFKitView(itemID: itemID, url: url, session: session)
            } else {
                ContentUnavailableView("PDF não encontrado", systemImage: "exclamationmark.triangle")
            }
        }
        .frame(maxWidth: 900)
        .padding(.top, 64)
        .padding(.bottom, 70)
    }
}
