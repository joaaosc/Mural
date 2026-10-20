import Foundation
import Testing

@testable import Mural

/// Qual pasta receberia o cartão arrastado se ele fosse solto agora.
@MainActor
struct FolderDropTrackerTests {
    private let first = UUID()
    private let second = UUID()

    @Test("Começando dentro de uma pasta, ela não é destino enquanto o ponteiro não sai")
    func startFolderIsNotATargetUntilThePointerLeaves() {
        var tracker = FolderDropTracker(startFolder: first)
        #expect(tracker.target == nil)

        tracker.update(folderUnderPointer: first)
        #expect(tracker.target == nil)
        #expect(tracker.startFolder == first, "o ponteiro ainda não saiu da pasta inicial")
    }

    @Test("Depois de sair da pasta inicial, voltar a ela a torna destino")
    func returningToStartFolderMakesItTheTarget() {
        var tracker = FolderDropTracker(startFolder: first)
        tracker.update(folderUnderPointer: nil)
        #expect(tracker.target == nil)

        tracker.update(folderUnderPointer: first)
        #expect(tracker.target == first)
    }

    @Test("Começando fora de qualquer pasta, entrar numa pasta a torna destino")
    func enteringAFolderFromOutsideMakesItTheTarget() {
        var tracker = FolderDropTracker(startFolder: nil)
        tracker.update(folderUnderPointer: nil)
        #expect(tracker.target == nil)

        tracker.update(folderUnderPointer: first)
        #expect(tracker.target == first)
    }

    @Test("Da pasta inicial direto para outra pasta, a outra vira destino")
    func goingStraightToAnotherFolderMakesItTheTarget() {
        var tracker = FolderDropTracker(startFolder: first)
        tracker.update(folderUnderPointer: second)
        #expect(tracker.target == second)
        #expect(tracker.startFolder == nil)
    }

    @Test("Sair do destino zera o destino")
    func leavingTheTargetClearsIt() {
        var tracker = FolderDropTracker(startFolder: nil)
        tracker.update(folderUnderPointer: first)
        #expect(tracker.target == first)

        tracker.update(folderUnderPointer: nil)
        #expect(tracker.target == nil)
    }
}
