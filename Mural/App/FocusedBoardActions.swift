import Foundation
import Observation

/// Comandos que pertencem à cena focada, nunca a um estado global de aplicativo.
@MainActor
@Observable
final class FocusedBoardActions {
    weak var session: BoardWindowSession?

    func addFiles() {
        session?.isImporterPresented = true
    }

    func retryFlush() {
        session?.retryFlush()
    }

    var currentBoardInfo: String {
        session?.title ?? "Nenhum mural focado"
    }
}
