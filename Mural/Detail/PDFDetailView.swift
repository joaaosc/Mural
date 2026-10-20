import PDFKit
import SwiftUI

/// Documento PDF com rolagem contínua e ajuste automático de tamanho.
struct PDFDetailView: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                PDFKitView(url: url)
            } else {
                ContentUnavailableView("PDF não encontrado", systemImage: "exclamationmark.triangle")
            }
        }
        .frame(maxWidth: 900)
        .padding(.top, 64)
        .padding(.bottom, 70)
    }
}

/// Ponte para o `PDFView` do PDFKit, que não tem equivalente em SwiftUI.
private struct PDFKitView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
