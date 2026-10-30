import Foundation
import MuralKit
import SwiftUI

extension BoardWindowSession {
    /// Cria um cartão de música para cada rascunho, na pasta pedida. A capa que veio no arrasto vai para o
    /// coordenador gravar; as demais ele baixa depois, pelo molde do endereço.
    @discardableResult
    func importMusic(
        _ drafts: [MusicDraft], into folderID: UUID?, at anchor: BoardPoint? = nil,
        artwork: MusicArtworkCoordinator?, animation: Animation?
    ) -> [UUID] {
        guard acceptsPersistence(for: boardID, generation: presentationGeneration), !isClosed, let model else { return [] }
        let created = withAnimation(animation) {
            model.importMusic(drafts.map(\.snapshot), into: folderID, at: anchor)
        }
        if created.isEmpty {
            model.lastError = "O conteúdo copiado não pôde virar um cartão."
        } else {
            for item in created {
                guard let key = item.music?.dedupeKey,
                    let data = drafts.first(where: { $0.snapshot.dedupeKey == key && $0.artworkData != nil })?.artworkData
                else { continue }
                artwork?.store(data, for: item.id)
            }
        }
        captureBoardIfNeeded()
        return created.map(\.id)
    }

    /// Toca, pausa ou retoma o cartão de música, pelo tocador do app.
    func toggleMusic(_ itemID: UUID) async {
        guard let model, !isClosed else { return }
        await musicPlayback.toggle(itemID, in: model, boardID: boardID, route: route, boardTitle: manifestName)
    }

    /// Toca ou pausa a música embutida numa nota, pelo mesmo tocador do cartão solto.
    func toggleEmbeddedMusic(_ embedded: EmbeddedMusic) async {
        guard let model, !isClosed else { return }
        await musicPlayback.toggle(
            embedded.cardID, in: model, boardID: boardID, route: route, boardTitle: manifestName, embedded: embedded)
    }

    /// Toca o cartão a partir de uma faixa (`nil`: do começo).
    func playMusic(_ itemID: UUID, startingAt trackID: String?) async {
        guard let model, !isClosed else { return }
        await musicPlayback.play(
            itemID, startingAt: trackID, in: model, boardID: boardID, route: route, boardTitle: manifestName)
    }

    /// Busca a capa e as cores no catálogo quando o cartão tem `catalogID` mas nenhuma capa. Só com acesso já
    /// concedido: nunca pede permissão.
    func completeMusicArtwork(_ itemID: UUID, artwork: MusicArtworkCoordinator?) async {
        guard let model, !isClosed, musicPlayback.access == .granted,
            let music = model.item(id: itemID)?.music, music.catalogID != nil, music.artworkTemplate == nil
        else { return }
        let files = LinkPreviewFiles(directory: LaunchConfiguration.linkPreviewsDirectory(for: boardID))
        guard music.artworkFile.flatMap({ files.existingURL(for: $0) }) == nil else { return }
        guard let found = await musicPlayback.catalogArtwork(for: music), !isClosed else { return }
        artwork?.download(found.url, for: itemID)
        // Relê o cartão: pode ter mudado durante a espera.
        guard var current = model.item(id: itemID)?.music else { return }
        current.backgroundHex = current.backgroundHex ?? found.backgroundHex
        current.primaryTextHex = current.primaryTextHex ?? found.primaryTextHex
        current.secondaryTextHex = current.secondaryTextHex ?? found.secondaryTextHex
        model.updateMusic(itemID, with: current)
    }

    func musicPhase(of itemID: UUID) -> MusicCardPhase {
        musicPlayback.phase(of: itemID)
    }

    /// Abre o item no app Música (ou no navegador, sem o app).
    func openMusicInApp(_ itemID: UUID) {
        guard let music = model?.item(id: itemID)?.music else { return }
        MusicOpener.open(music)
    }
}
