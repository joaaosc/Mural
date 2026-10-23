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
        await musicPlayback.toggle(itemID, in: model, boardID: boardID)
    }

    /// Toca o cartão a partir de uma faixa (`nil`: do começo).
    func playMusic(_ itemID: UUID, startingAt trackID: String?) async {
        guard let model, !isClosed else { return }
        await musicPlayback.play(itemID, startingAt: trackID, in: model, boardID: boardID)
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
