import AppKit
import Foundation
import GroupActivities

/// Como terminou o pedido de começar o Live Share.
nonisolated enum LiveStartOutcome: Equatable, Sendable {
    /// O sistema começou a atividade: a sessão chega por `MuralLiveActivity.sessions()`.
    case started
    /// A pessoa desistiu, escolheu não compartilhar, ou a sessão foi para outro aparelho.
    case notStarted
}

/// O que impede de começar o Live Share.
nonisolated enum LiveShareError: LocalizedError {
    /// Sem a janela do Mural não há onde abrir a folha do sistema.
    case noWindow

    var errorDescription: String? {
        switch self {
        case .noWindow: "Abra a janela do Mural para começar o Live Share."
        }
    }
}

/// Quem começa a atividade do Live Share no sistema. O de verdade é o `SharePlayStarter`; os testes usam outro.
@MainActor
protocol LiveActivityStarter: AnyObject {
    /// Há uma chamada do FaceTime em que a atividade começa direto, sem a folha de escolher pessoas.
    var isInCall: Bool { get }
    /// Com chamada: `prepareForActivation()` e, se `.activationPreferred`, `activate()`. Sem chamada: a folha do sistema para
    /// escolher pessoas e ligar (`GroupActivitySharingController`), como folha da janela dada.
    func start(_ activity: MuralLiveActivity, in window: NSWindow?) async throws -> LiveStartOutcome
}

/// O início de verdade, pelo SharePlay. Não tem teste automático: precisa de uma chamada do FaceTime ou da folha do sistema.
@MainActor
final class SharePlayStarter: LiveActivityStarter {
    private let observer = GroupStateObserver()

    var isInCall: Bool { observer.isEligibleForGroupSession }

    /// - Throws: `LiveShareError.noWindow` sem chamada e sem janela para a folha; ou o que `activate()` e o controlador da folha lançarem.
    func start(_ activity: MuralLiveActivity, in window: NSWindow?) async throws -> LiveStartOutcome {
        isInCall ? try await startInCall(activity) : try await startWithSheet(activity, in: window)
    }

    /// Na chamada a atividade começa direto. `activate()` devolve `false` quando a sessão foi para outro aparelho da pessoa: nada
    /// chega a este Mac, e não adianta esperar nem repetir.
    private func startInCall(_ activity: MuralLiveActivity) async throws -> LiveStartOutcome {
        switch await activity.prepareForActivation() {
        case .activationPreferred:
            return try await activity.activate() ? .started : .notStarted
        case .activationDisabled, .cancelled:
            return .notStarted
        @unknown default:
            return .notStarted
        }
    }

    /// Sem chamada, a folha do sistema escolhe as pessoas e liga para elas. Depois de `.success` o sistema já começou a atividade:
    /// não se chama `activate()`.
    private func startWithSheet(_ activity: MuralLiveActivity, in window: NSWindow?) async throws -> LiveStartOutcome {
        guard let presenter = window?.contentViewController else { throw LiveShareError.noWindow }
        let controller = try GroupActivitySharingController(activity)
        presenter.presentAsSheet(controller)
        let result = await controller.result
        if controller.presentingViewController != nil { presenter.dismiss(controller) }
        return result == .success ? .started : .notStarted
    }
}
