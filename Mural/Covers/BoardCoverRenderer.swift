import CoreGraphics
import MuralKit
import SwiftUI
import os

/// Desenha a capa de um mural numa imagem.
///
/// As miniaturas carregam de forma assíncrona e o `ImageRenderer` desenha uma vez só, lendo o cache de forma síncrona.
/// Por isso as miniaturas que os cartões vão pedir são carregadas antes (`thumbnailRequests`): sem isso, as fotos
/// sairiam como quadros cinza de carregamento.
enum BoardCoverRenderer {
    /// Quantos cartões soltos entram na capa; com mais, ficam os mais recentes.
    static let maximumItems = 120
    /// Pixels por ponto: a capa de 320 × 200 pontos sai com 640 × 400 pixels.
    static let scale: CGFloat = 2

    /// Quantas miniaturas carregam ao mesmo tempo ao preparar uma capa.
    private static let maximumConcurrentThumbnails = 4
    /// Maior lado da miniatura de foto, vídeo e PDF: o padrão do `ThumbnailView`, que o `MediaCard` usa.
    private static let mediaMaxPixelSize = ThumbnailView(url: nil, kind: .image).maxPixelSize
    /// Maior lado das miniaturas do leque da pasta, o mesmo de `FolderPeekTile`.
    private static let folderPeekMaxPixelSize = 240
    private static let signposter = OSSignposter(subsystem: "com.joaocosta.Mural", category: "Capas")

    /// As miniaturas que os cartões da capa vão pedir ao `ThumbnailCache`, na ordem do mural e sem repetir.
    ///
    /// São os mesmos pedidos que cada cartão faz ao ser desenhado (tipo e tamanho inclusive), porque o cache
    /// guarda por endereço, tipo e tamanho: uma miniatura de outro tamanho não serve. Imagens dentro de notas ficam
    /// de fora, e o cartão que depende delas pode sair cinza na capa.
    /// - Parameter linkPreviewFiles: a pasta das prévias dos links e das capas de música do mural; sem ela, só
    ///   foto, vídeo e PDF geram pedidos.
    static func thumbnailRequests(
        for layout: BoardCoverLayout, model: BoardModel, linkPreviewFiles: LinkPreviewFiles?
    ) -> [ThumbnailRequest] {
        var requests: [ThumbnailRequest] = []
        var seen = Set<ThumbnailRequest>()
        func add(_ url: URL?, kind: ItemKind, maxPixelSize: Int) {
            guard let url else { return }
            let request = ThumbnailRequest(url: url, kind: kind, maxPixelSize: maxPixelSize)
            if seen.insert(request).inserted { requests.append(request) }
        }

        for item in layout.items {
            switch item.kind {
            case .image, .video, .pdf:
                // `MediaCard`: o arquivo do cartão.
                add(model.fileURL(for: item), kind: item.kind, maxPixelSize: mediaMaxPixelSize)
            case .link:
                // `LinkCard`: a imagem de prévia e o ícone do site, se os arquivos estão na pasta.
                if let name = item.link?.previewImageFile {
                    add(linkPreviewFiles?.existingURL(for: name), kind: .image, maxPixelSize: LinkCard.imageMaxPixelSize)
                }
                if let name = item.link?.iconFile {
                    add(linkPreviewFiles?.existingURL(for: name), kind: .image, maxPixelSize: LinkCard.iconMaxPixelSize)
                }
            case .music:
                // `MusicCard`: a capa do álbum, se o arquivo está na pasta.
                if let music = item.music, let name = music.artworkFile {
                    add(linkPreviewFiles?.existingURL(for: name), kind: .image, maxPixelSize: MusicArtwork(music: music).maxPixelSize)
                }
            case .folder:
                let peeks = FolderPeekItem.latest(
                    model.children(of: item.id), fileURL: model.fileURL(for:),
                    linkPreviewURL: { FolderPeekItem.linkPreviewURL(of: $0, in: linkPreviewFiles) })
                for peek in peeks {
                    // `FolderPeekTile`: foto, vídeo e PDF pelo próprio tipo; link e música pela imagem de prévia.
                    switch peek.kind {
                    case .image, .video, .pdf:
                        add(peek.fileURL, kind: peek.kind, maxPixelSize: folderPeekMaxPixelSize)
                    case .link, .music:
                        add(peek.fileURL, kind: .image, maxPixelSize: folderPeekMaxPixelSize)
                    case .text, .checklist, .sticky, .reminder, .folder:
                        break
                    }
                }
            case .text, .checklist, .sticky, .reminder:
                break
            }
        }
        return requests
    }

    /// Desenha a capa de `board`.
    ///
    /// - Parameters:
    ///   - board: o conteúdo a desenhar (o do disco ou o do modelo vivo).
    ///   - model: o modelo que os cartões consultam (arquivos de `Items/` e conteúdo das pastas). Nada é gravado nele.
    ///   - linkPreviewFiles: a pasta das prévias dos links e das capas de música do mural.
    /// - Returns: a imagem opaca, ou `nil` se o `ImageRenderer` não gerou nenhuma.
    static func render(board: Board, model: BoardModel, linkPreviewFiles: LinkPreviewFiles?) async -> CGImage? {
        let layout = BoardCoverLayout.make(
            for: board, coverWidth: BoardCoverView.size.width, coverHeight: BoardCoverView.size.height,
            maximumItems: maximumItems)

        let warming = signposter.beginInterval("Aquecer miniaturas")
        await warm(thumbnailRequests(for: layout, model: model, linkPreviewFiles: linkPreviewFiles))
        signposter.endInterval("Aquecer miniaturas", warming)

        // Sem nada suspenso daqui até o `cgImage`: as miniaturas aquecidas ainda estão no cache.
        let drawing = signposter.beginInterval("Desenhar capa")
        defer { signposter.endInterval("Desenhar capa", drawing) }
        let renderer = ImageRenderer(
            content: BoardCoverView(layout: layout, model: model).environment(\.linkPreviewFiles, linkPreviewFiles))
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.cgImage
    }

    /// Carrega as miniaturas no cache compartilhado, no máximo `maximumConcurrentThumbnails` por vez. Uma que não
    /// carrega (arquivo ausente ou ilegível) é só ignorada: o cartão sai com o quadro cinza de carregamento.
    private static func warm(_ requests: [ThumbnailRequest]) async {
        guard !requests.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            var remaining = requests.makeIterator()
            for _ in 0..<maximumConcurrentThumbnails {
                guard let request = remaining.next() else { break }
                group.addTask { _ = await ThumbnailCache.shared.image(for: request) }
            }
            // Cada miniatura pronta libera a vaga para a próxima.
            while await group.next() != nil {
                guard let request = remaining.next() else { continue }
                group.addTask { _ = await ThumbnailCache.shared.image(for: request) }
            }
        }
    }
}
