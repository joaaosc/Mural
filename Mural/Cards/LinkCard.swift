import MuralKit
import SwiftUI

/// Cartão de link em miniatura: a imagem de prévia da página (ou, sem ela, o monograma do site)
/// no topo e, abaixo, o site, o título e o resumo.
///
/// As fontes são fixas de propósito, como nas notas: o cartão é uma miniatura da página,
/// não texto para leitura.
struct LinkCard: View {
    let item: BoardItem

    @Environment(\.linkPreviewFiles) private var files
    @Environment(\.linkPreviewCoordinator) private var coordinator

    /// Proporção (largura ÷ altura) da área da imagem: a das imagens de prévia que os sites publicam.
    static let imageAspectRatio: CGFloat = 1.91
    /// Maior lado, em pixels, da miniatura da imagem de prévia.
    static let imageMaxPixelSize = 480
    /// Maior lado, em pixels, da miniatura do ícone (o arquivo guardado já tem no máximo 64).
    static let iconMaxPixelSize = 64

    private var link: LinkInfo? { item.link }
    private var host: String { link?.displayHost ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover
            VStack(alignment: .leading, spacing: 4) {
                siteRow
                Text(item.title)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(2)
                if let summary = link?.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 5.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(.rect(cornerRadius: Theme.cardCorner))
        // A sombra é só do papel: aplicada ao cartão inteiro, a imagem e cada texto ganhariam a sua,
        // e a da imagem cairia sobre o papel logo abaixo dela.
        .background {
            RoundedRectangle(cornerRadius: Theme.cardCorner)
                .fill(Theme.paper)
                .cardShadow()
        }
        // A política do domínio ignora prévia pronta (com os arquivos no lugar) ou falha recente, então pedir a cada
        // aparição é barato. Com o arquivo faltando, o pedido refaz a busca e o cartão deixa de ficar no monograma.
        .task(id: PreviewTrigger(itemID: item.id, coordinator: coordinator.map(ObjectIdentifier.init))) {
            coordinator?.request([item.id])
        }
    }

    /// Refaz o pedido quando o cartão muda ou quando o coordenador passa a existir: ele é criado depois
    /// da primeira exibição dos cartões da janela.
    private struct PreviewTrigger: Equatable {
        let itemID: UUID
        let coordinator: ObjectIdentifier?
    }

    // MARK: Topo

    /// Área da imagem, sempre na proporção fixa e na largura do cartão: o que passar dela é recortado.
    private var cover: some View {
        Color.clear
            .aspectRatio(Self.imageAspectRatio, contentMode: .fit)
            .overlay { coverContent }
            .clipped()
            // A altura vem só da largura, qualquer que seja a altura que o cartão receba.
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A imagem de prévia, se o arquivo está na pasta; sem ele (a pasta pode não acompanhar o mural), o monograma.
    @ViewBuilder
    private var coverContent: some View {
        if let name = link?.previewImageFile, let url = files?.existingURL(for: name) {
            ThumbnailView(url: url, kind: .image, maxPixelSize: Self.imageMaxPixelSize)
        } else {
            monogram
        }
    }

    /// Sem imagem: a inicial do site em branco sobre uma cor que só depende do host.
    private var monogram: some View {
        Color(hue: LinkMonogram.hue(for: host), saturation: 0.35, brightness: 0.82)
            .overlay {
                Text(LinkMonogram.letter(for: host))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
    }

    // MARK: Site

    private var siteRow: some View {
        HStack(spacing: 3) {
            siteIcon
            Text(link?.displaySiteName ?? host)
                .font(.system(size: 6.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// O ícone do site, se o arquivo está na pasta; sem ele, um globo.
    @ViewBuilder
    private var siteIcon: some View {
        if let name = link?.iconFile, let url = files?.existingURL(for: name) {
            ThumbnailView(url: url, kind: .image, maxPixelSize: Self.iconMaxPixelSize, contentMode: .fit)
                .frame(width: 10, height: 10)
                .clipShape(.rect(cornerRadius: 2))
        } else {
            Image(systemName: "globe")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .frame(width: 10, height: 10)
        }
    }
}
