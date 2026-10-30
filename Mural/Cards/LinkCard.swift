import MuralKit
import SwiftUI

/// Cartão de link em miniatura: a imagem de prévia da página (ou, sem ela, o monograma do site)
/// no topo e, abaixo, o site, o título e o resumo.
///
/// As fontes são fixas de propósito, como nas notas: o cartão é uma miniatura da página,
/// não texto para leitura.
struct LinkCard: View {
    let item: BoardItem

    @Environment(\.linkPreviewCoordinator) private var coordinator
    @Environment(\.remoteContentAllowed) private var remoteContentAllowed

    /// Proporção (largura ÷ altura) da área da imagem: a das imagens de prévia que os sites publicam.
    static let imageAspectRatio: CGFloat = 1.91
    /// Maior lado, em pixels, da miniatura da imagem de prévia.
    static let imageMaxPixelSize = 480
    /// Maior lado, em pixels, da miniatura do ícone (o arquivo guardado já tem no máximo 64).
    static let iconMaxPixelSize = 64

    var body: some View {
        if let link = item.link {
            LinkCardContent(link: link, title: item.title)
                // A política do domínio ignora prévia pronta (com os arquivos no lugar) ou falha recente, então pedir a cada
                // aparição é barato. Com o arquivo faltando, o pedido refaz a busca e o cartão deixa de ficar no monograma.
                .task(
                    id: PreviewTrigger(
                        itemID: item.id, coordinator: coordinator.map(ObjectIdentifier.init), isAllowed: remoteContentAllowed)
                ) {
                    coordinator?.request([item.id])
                }
        } else {
            CardTitleFallback(title: item.title)
        }
    }

    /// Refaz o pedido quando o cartão muda ou quando o coordenador passa a existir: ele é criado depois
    /// da primeira exibição dos cartões da janela, ou quando a pessoa permite buscar na internet.
    private struct PreviewTrigger: Equatable {
        let itemID: UUID
        let coordinator: ObjectIdentifier?
        let isAllowed: Bool
    }
}
