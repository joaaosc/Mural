import Foundation
import MuralKit
import Observation
import SwiftUI

enum FocusedBoardActionRequest: Equatable, Sendable {
    case newBoard
    case openMural
    case rename
    case resumeDraft
    case promoteDraft
    case newFolder
    case tileBoard
}

enum MuralCommandIntent: Equatable, Sendable {
    case newBoard
    case openMural
}

struct MuralCommandRequest: Equatable, Sendable {
    let token: UInt64
    let intent: MuralCommandIntent
}

/// App-scoped hand-off for commands issued while no scene is focused.  The
/// request is consumed by the library scene exactly once; it is not global
/// process state and does not identify a board.
@MainActor
@Observable
final class MuralCommandCoordinator {
    private(set) var pending: MuralCommandRequest?
    private var nextToken: UInt64 = 0

    @discardableResult
    func submit(_ intent: MuralCommandIntent) -> UInt64 {
        nextToken &+= 1
        let request = MuralCommandRequest(token: nextToken, intent: intent)
        pending = request
        return request.token
    }

    func consume(token: UInt64) -> MuralCommandIntent? {
        guard let pending, pending.token == token else { return nil }
        self.pending = nil
        return pending.intent
    }
}

private struct MuralCommandCoordinatorKey: EnvironmentKey {
    static let defaultValue: MuralCommandCoordinator? = nil
}

extension EnvironmentValues {
    var muralCommandCoordinator: MuralCommandCoordinator? {
        get { self[MuralCommandCoordinatorKey.self] }
        set { self[MuralCommandCoordinatorKey.self] = newValue }
    }
}

/// Comandos que pertencem à cena focada, nunca a um estado global de aplicativo.
@MainActor
@Observable
final class FocusedBoardActions {
    weak var session: BoardWindowSession?
    var request: FocusedBoardActionRequest?
    /// Library scenes set this from the persisted lifecycle.  It is not
    /// inferred from a route because a promoted welcome ID is no longer a
    /// valid draft route.
    var resumeDraftAvailable = false

    func addFiles() {
        session?.beginFileImport(folderID: session?.currentFolderID)
    }

    func saveDraft() {
        request = .promoteDraft
    }

    func saveCopy() {
        session?.beginSaveCopy()
    }

    func newBoard() {
        request = .newBoard
    }

    func openMural() {
        request = .openMural
    }

    func rename() {
        request = .rename
    }

    func resumeDraft() {
        request = .resumeDraft
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

    /// Nova pasta só no mural, com nada aberto por cima (pastas não entram em pastas).
    var canCreateFolder: Bool {
        session?.acceptsNewFolder ?? false
    }

    var canTileBoard: Bool {
        session?.canTileBoard ?? false
    }

    var canRename: Bool {
        session?.model != nil
    }

    var canResumeDraft: Bool {
        if let session {
            return session.model != nil && resumeDraftAvailable
        }
        return resumeDraftAvailable
    }
}
