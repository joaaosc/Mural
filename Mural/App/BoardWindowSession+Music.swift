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
}
