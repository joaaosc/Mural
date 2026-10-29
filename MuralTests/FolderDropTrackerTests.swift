import Foundation
import Testing

@testable import Mural

/// Qual pasta receberia o cartão arrastado se ele fosse solto agora.
@MainActor
struct FolderDropTrackerTests {
    private let first = UUID()
    private let second = UUID()
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    /// Passa a espera completa sobre a candidata atual.
    private func armed(_ tracker: inout FolderDropTracker) {
        tracker.arm(now: t0.addingTimeInterval(FolderDropTracker.armingDelay))
    }

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

        tracker.update(folderUnderPointer: first, now: t0)
        #expect(tracker.candidate == first)
        armed(&tracker)
        #expect(tracker.target == first)
    }

    @Test("Começando fora de qualquer pasta, entrar numa pasta a torna destino")
    func enteringAFolderFromOutsideMakesItTheTarget() {
        var tracker = FolderDropTracker(startFolder: nil)
        tracker.update(folderUnderPointer: nil)
        #expect(tracker.target == nil)

        tracker.update(folderUnderPointer: first, now: t0)
        armed(&tracker)
        #expect(tracker.target == first)
    }

    @Test("Da pasta inicial direto para outra pasta, a outra vira destino")
    func goingStraightToAnotherFolderMakesItTheTarget() {
        var tracker = FolderDropTracker(startFolder: first)
        tracker.update(folderUnderPointer: second, now: t0)
        armed(&tracker)
        #expect(tracker.target == second)
        #expect(tracker.startFolder == nil)
    }

    @Test("Sair do destino zera o destino")
    func leavingTheTargetClearsIt() {
        var tracker = FolderDropTracker(startFolder: nil)
        tracker.update(folderUnderPointer: first, now: t0)
        armed(&tracker)
        #expect(tracker.target == first)

        tracker.update(folderUnderPointer: nil, now: t0.addingTimeInterval(2))
        #expect(tracker.target == nil)
        #expect(tracker.candidate == nil)
    }

    @Test("A pasta só aceita o cartão depois de 1 s sob o ponteiro")
    func armsOnlyAfterTheDelay() {
        var tracker = FolderDropTracker(startFolder: nil)
        tracker.update(folderUnderPointer: first, now: t0)
        #expect(tracker.candidate == first)
        #expect(tracker.target == nil)

        let didArm1 = tracker.arm(now: t0.addingTimeInterval(0.99))
        #expect(!didArm1)
        #expect(tracker.target == nil)

        let didArm2 = tracker.arm(now: t0.addingTimeInterval(1))
        #expect(didArm2)
        #expect(tracker.isArmed)
        #expect(tracker.target == first)
        let didArm3 = tracker.arm(now: t0.addingTimeInterval(1.5))
        #expect(!didArm3, "só avisa uma vez")
    }

    @Test("Continuar sobre a mesma pasta não reinicia a espera")
    func stayingOverTheSameFolderKeepsTheClock() {
        var tracker = FolderDropTracker(startFolder: nil)
        tracker.update(folderUnderPointer: first, now: t0)
        tracker.update(folderUnderPointer: first, now: t0.addingTimeInterval(0.8))
        let didArm1 = tracker.arm(now: t0.addingTimeInterval(1))
        #expect(didArm1)
    }

    @Test("Sair da pasta e voltar recomeça a espera")
    func leavingResetsTheWait() {
        var tracker = FolderDropTracker(startFolder: nil)
        tracker.update(folderUnderPointer: first, now: t0)
        tracker.update(folderUnderPointer: nil, now: t0.addingTimeInterval(0.9))
        tracker.update(folderUnderPointer: first, now: t0.addingTimeInterval(1.0))

        let didArm1 = tracker.arm(now: t0.addingTimeInterval(1.5))
        #expect(!didArm1)
        let didArm2 = tracker.arm(now: t0.addingTimeInterval(2.0))
        #expect(didArm2)
    }

    @Test("Trocar de pasta recomeça a espera e desfaz a liberação")
    func switchingFoldersResetsTheWait() {
        var tracker = FolderDropTracker(startFolder: nil)
        tracker.update(folderUnderPointer: first, now: t0)
        armed(&tracker)
        #expect(tracker.target == first)

        tracker.update(folderUnderPointer: second, now: t0.addingTimeInterval(1.1))
        #expect(tracker.candidate == second)
        #expect(tracker.target == nil)
        let didArm1 = tracker.arm(now: t0.addingTimeInterval(1.9))
        #expect(!didArm1)
        let didArm2 = tracker.arm(now: t0.addingTimeInterval(2.1))
        #expect(didArm2)
        #expect(tracker.target == second)
    }

    @Test("A pasta inicial nunca vira candidata enquanto o ponteiro não sai")
    func startFolderNeverArms() {
        var tracker = FolderDropTracker(startFolder: first)
        tracker.update(folderUnderPointer: first, now: t0)
        #expect(tracker.candidate == nil)
        let didArm1 = tracker.arm(now: t0.addingTimeInterval(5))
        #expect(!didArm1)
        #expect(tracker.target == nil)
    }
}
