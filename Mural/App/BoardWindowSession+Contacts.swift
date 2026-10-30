import Foundation
import MuralKit
import SwiftUI

extension BoardWindowSession {
    /// O armazém das fotos dos contatos desta sessão, criado na primeira vez. `nil` sem o mural carregado.
    func contactThumbnailStore() -> ContactThumbnailStore? {
        if let contactThumbnails { return contactThumbnails }
        guard let model else { return nil }
        let files = LinkPreviewFiles(directory: LaunchConfiguration.linkPreviewsDirectory(for: boardID))
        let store = ContactThumbnailStore(model: model, files: files, isActive: { [weak self] in self.map { !$0.isClosed } ?? false })
        contactThumbnails = store
        return store
    }

    /// Cria um cartão de contato para cada rascunho, na pasta pedida, e manda gravar as fotos.
    @discardableResult
    func importContacts(
        _ drafts: [ContactDraft], into folderID: UUID?, at anchor: BoardPoint? = nil, animation: Animation?
    ) -> [UUID] {
        guard acceptsPersistence(for: boardID, generation: presentationGeneration), !isClosed, let model else { return [] }
        let created = withAnimation(animation) {
            model.importContacts(drafts.map(\.snapshot), into: folderID, at: anchor)
        }
        if created.isEmpty {
            model.lastError = "O conteúdo copiado não pôde virar um cartão."
        } else {
            contactThumbnailStore()?.store(drafts, for: created)
        }
        captureBoardIfNeeded()
        return created.map(\.id)
    }
}
