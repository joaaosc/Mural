import MuralKit
import SwiftUI

/// Capa de um item do Apple Music: o arquivo guardado, se está na pasta de prévias; sem ele, a cor da capa
/// (ou um papel um pouco mais escuro) com o símbolo do tipo no centro. Preenche o espaço que recebe, recortando.
struct MusicArtwork: View {
    let music: MusicSnapshot
    var maxPixelSize = 480

    @Environment(\.linkPreviewFiles) private var files

    var body: some View {
        Color.clear
            .overlay { content }
            .clipped()
    }

    @ViewBuilder
    private var content: some View {
        if let name = music.artworkFile, let url = files?.existingURL(for: name) {
            ThumbnailView(url: url, kind: .image, maxPixelSize: maxPixelSize)
        } else {
            (Color(muralHex: music.backgroundHex) ?? Theme.paper.mix(with: .black, by: 0.08))
                .overlay {
                    Image(systemName: music.kind.symbol)
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(
                            Color(muralHex: music.primaryTextHex) ?? Color.readable(onHex: music.backgroundHex) ?? .secondary
                        )
                        .accessibilityHidden(true)
                }
        }
    }
}

/// Cartão de música em miniatura: a capa quadrada no topo e, abaixo, o tipo, o título e o artista.
///
/// Desenhado só pelo estado guardado no cartão (`MusicCardContent`); aqui ficam o pedido da capa e a janela de cada cartão.
struct MusicCard: View {
    let item: BoardItem

    @Environment(\.musicArtworkCoordinator) private var artwork
    @Environment(\.remoteContentAllowed) private var remoteContentAllowed
    @Environment(\.linkPreviewFiles) private var files

    var body: some View {
        if let music = item.music {
            MusicCardContent(music: music, title: item.title)
                // Sem a capa na pasta (cartão novo, pasta apagada), pede ao coordenador da janela.
                .task(id: ArtworkTrigger(file: music.artworkFile, isAllowed: remoteContentAllowed)) {
                    guard music.artworkFile.flatMap({ files?.existingURL(for: $0) }) == nil else { return }
                    artwork?.request([item.id])
                }
        } else {
            CardTitleFallback(title: item.title)
        }
    }

    /// Refaz o pedido quando a capa muda ou quando a pessoa permite buscar na internet.
    private struct ArtworkTrigger: Equatable {
        let file: String?
        let isAllowed: Bool
    }
}

/// Álbum com cores, faixa sem capa e playlist só com nome, no claro e no escuro.
private struct MusicCardSamples: View {
    var body: some View {
        HStack(spacing: 16) {
            sample(
                MusicSnapshot(
                    kind: .album, title: "Abbey Road", subtitle: "The Beatles", backgroundHex: "#1f3a5f",
                    primaryTextHex: "#ffffff", secondaryTextHex: "#c9d6e8", trackCount: 17))
            sample(MusicSnapshot(kind: .song, title: "Something", subtitle: "The Beatles", duration: 183))
            sample(MusicSnapshot(kind: .playlist, title: "Para ouvir de manhã"))
        }
    }

    private func sample(_ music: MusicSnapshot) -> some View {
        MusicCard(item: BoardItem(kind: .music, title: music.title, music: music))
            .frame(width: 150, height: 210)
    }
}

#Preview("Claro", traits: .fixedLayout(width: 540, height: 260)) {
    MusicCardSamples().padding(20).background(Theme.canvas)
}

#Preview("Escuro", traits: .fixedLayout(width: 540, height: 260)) {
    MusicCardSamples().padding(20).background(Theme.canvas).preferredColorScheme(.dark)
}
