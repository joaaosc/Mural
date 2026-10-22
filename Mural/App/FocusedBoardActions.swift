import Foundation
import MuralKit
import Observation
import SwiftUI

enum FocusedBoardActionRequest: Equatable, Sendable {
    case rename
    case promoteDraft
    case newFolder
    case tileBoard
}

/// Comandos que pertencem à cena focada, nunca a um estado global de aplicativo.
@MainActor
@Observable
final class FocusedBoardActions {
    weak var session: BoardWindowSession?
    var request: FocusedBoardActionRequest?

    func addFiles() {
        session?.beginFileImport(folderID: session?.currentFolderID)
    }

    func saveDraft() {
        request = .promoteDraft
    }

    func saveCopy() {
        session?.beginSaveCopy()
    }

    func rename() {
        request = .rename
    }

    func newNote() {
        session?.createCard(.text)
    }

    func newSticky() {
        session?.createCard(.sticky)
    }

    /// Pede o nome antes de criar: a folha é da cena focada.
    func newFolder() {
        request = .newFolder
    }

    /// A cena focada organiza: ela conhece o formato da janela e a pilha de desfazer.
    func tileBoard() {
        request = .tileBoard
    }

    func retryFlush() {
        session?.retryFlush()
    }

    var canSaveDraft: Bool {
        guard let session else { return false }
        switch session.route {
        case .welcomeDraft(_):
            return session.model != nil
        case .library, .saved(_):
            return false
        }
    }

    var canSaveCopy: Bool {
        guard let session else { return false }
        return session.model != nil && !session.isPreparingExport
            && !session.isFinishingExport
            && session.exportTransfer == nil && !session.isExporterPresented
    }

    var canAddFiles: Bool {
        session?.model != nil
    }

    /// Criar card ou sticker só no mural e dentro de pasta, não na página de um item.
    var canCreateContent: Bool {
        session?.acceptsNewContent ?? false
    }

    /// Nova pasta no mural ou dentro de uma pasta, até o último nível permitido.
    var canCreateFolder: Bool {
        session?.acceptsNewFolder ?? false
    }

    var canTileBoard: Bool {
        session?.canTileBoard ?? false
    }

    var canRename: Bool {
        session?.model != nil
    }
}
