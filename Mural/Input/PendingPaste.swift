import Foundation
import MuralKit

/// Texto solto colado que espera a escolha do tipo de cartão no popup.
struct PendingPaste: Identifiable, Equatable {
    let id = UUID()
    let text: String
    /// Pasta aberta no momento de colar: o cartão entra nela.
    let folderID: UUID?
    /// Centro visível no momento de colar, em coordenadas lógicas do mural.
    let anchor: BoardPoint?
    let choice: PasteChoice

    init(text: String, folderID: UUID?, anchor: BoardPoint? = nil) {
        self.text = text
        self.folderID = folderID
        self.anchor = anchor
        self.choice = ContentClassifier.pasteChoice(forText: text)
    }

    /// Começo do texto, para a prévia do popup.
    var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 400 ? String(trimmed.prefix(400)) + "…" : trimmed
    }
}
