import AppKit

/// O toque no trackpad Force Touch quando algo encaixa: proporção da imagem, pasta liberada e miniplayer.
///
/// O padrão `.levelChange` sozinho é fraco; por isso o toque é duplo, com `doubleTapInterval` entre as duas batidas. O
/// `.sensoryFeedback` do SwiftUI não deixa repetir nem desligar o toque com uma opção da pessoa.
@MainActor
enum HapticFeedback {
    /// A chave, em `UserDefaults`, do retorno tátil (ligado por padrão).
    static let enabledKey = "hapticFeedbackEnabled"

    /// O intervalo entre as duas batidas do toque duplo.
    static let doubleTapInterval = Duration.milliseconds(40)

    /// Se a pessoa deixou o retorno tátil ligado; sem valor gravado, está ligado.
    static func isEnabled(in preferences: UserDefaults = .standard) -> Bool {
        preferences.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Dá o toque duplo, se o retorno tátil estiver ligado. `isEnabled` e `perform` existem para os testes trocarem.
    static func play(
        isEnabled: () -> Bool = { HapticFeedback.isEnabled() },
        perform: @escaping @MainActor () -> Void = systemTap
    ) {
        guard isEnabled() else { return }
        perform()
        Task {
            try? await Task.sleep(for: doubleTapInterval)
            perform()
        }
    }

    /// Uma batida no trackpad do sistema.
    static func systemTap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
