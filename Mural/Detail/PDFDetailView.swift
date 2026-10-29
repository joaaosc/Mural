import SwiftUI

/// Documento PDF com rolagem contínua e ajuste automático de tamanho.
struct PDFDetailView: View {
    let itemID: UUID
    let url: URL?
    let session: BoardWindowSession?

    @State private var loadState: PDFLoadState = .loading
    @State private var retryID = UUID()

    var body: some View {
        Group {
            if let url {
                ZStack {
                    PDFKitView(itemID: itemID, url: url, session: session, onLoadStateChange: { loadState = $0 })
                        .id(retryID)
                    switch loadState {
                    case .loading:
                        ProgressView("Carregando PDF…")
                            .padding(12)
                            .background(.regularMaterial, in: .rect(cornerRadius: 10))
                            .allowsHitTesting(false)
                    case .loaded:
                        EmptyView()
                    case .failed:
                        ContentUnavailableView {
                            Label("Não foi possível abrir este PDF", systemImage: "doc.text.magnifyingglass")
                        } description: {
                            Text("O arquivo pode estar indisponível ou inválido.")
                        } actions: {
                            Button("Tentar novamente", systemImage: "arrow.clockwise") {
                                loadState = .loading
                                retryID = UUID()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("PDF não encontrado", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("O arquivo deste item não está disponível.")
                }
            }
        }
        .frame(maxWidth: 900)
        .padding(.top, 64)
        .padding(.bottom, 70)
    }
}
