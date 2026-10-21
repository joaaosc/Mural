import MuralKit
import SwiftUI

/// Ocupa o lugar da página quando ela não abre (sem rede, site fora do ar, endereço `http` sem `https`...):
/// mostra o cartão, com imagem de prévia, título, site e resumo, e as duas saídas.
struct LinkFailureView: View {
    let item: BoardItem
    /// O motivo, como o sistema o descreve.
    let message: String
    let files: LinkPreviewFiles?
    var onRetry: () -> Void
    var onOpenInBrowser: () -> Void

    private var link: LinkInfo? { item.link }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                cover
                VStack(spacing: 8) {
                    Text(item.title)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    Text(link?.displaySiteName ?? "")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    if let summary = link?.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                    }
                }
                VStack(spacing: 4) {
                    Label("Não foi possível abrir a página", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 10) {
                    Button("Tentar de novo", action: onRetry)
                        .buttonStyle(.borderedProminent)
                    Button("Abrir no navegador", action: onOpenInBrowser)
                }
            }
            .frame(maxWidth: 420)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.page)
    }

    // MARK: Topo

    /// A imagem de prévia na proporção do cartão; sem ela, o ícone do site ou um globo.
    @ViewBuilder
    private var cover: some View {
        // Arquivo de prévia que sumiu conta como ausente: cai no ícone ou no globo, nunca num quadro cinza.
        if let name = link?.previewImageFile, let url = files?.existingURL(for: name) {
            Color.clear
                .aspectRatio(LinkCard.imageAspectRatio, contentMode: .fit)
                .overlay { ThumbnailView(url: url, kind: .image, maxPixelSize: 960) }
                .clipShape(.rect(cornerRadius: Theme.mediaCorner))
                .frame(maxWidth: 360)
                .accessibilityHidden(true)
        } else if let name = link?.iconFile, let url = files?.existingURL(for: name) {
            ThumbnailView(url: url, kind: .image, maxPixelSize: 128, contentMode: .fit)
                .frame(width: 56, height: 56)
                .clipShape(.rect(cornerRadius: 12))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "globe")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}
