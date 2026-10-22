import Foundation
import MuralKit

extension BoardWindowSession {
    /// Marca ou desmarca a tarefa do bloco `segment`, a partir do texto que a página mostra.
    /// Os parágrafos abertos continuam abertos: só a caixa muda.
    func toggleNoteTask(_ itemID: UUID, segment: Int, source: String) {
        guard !isClosed, let model else { return }
        let open = openStretchIDs(for: itemID, source: source)
        guard model.toggleNoteTask(itemID, segment: segment, in: source) else { return }
        if !open.isEmpty, let updated = model.item(id: itemID)?.text {
            recordOpenStretches(Set(open), for: itemID, source: updated)
        }
        captureBoardIfNeeded()
    }
}
