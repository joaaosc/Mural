import SwiftUI

extension View {
    /// Libera a tela se a restauração da posição de leitura não terminar a tempo.
    ///
    /// Enquanto restaura, a tela fica sem clique e oculta da acessibilidade; um alvo
    /// inalcançável (conteúdo menor que o salvo, arredondamento de pixel) a deixaria
    /// assim para sempre. Uma posição aproximada é melhor que uma tela presa.
    func readingRestoreTimeout(
        isRestoring: Bool,
        after delay: Duration = .milliseconds(1500),
        onTimeout: @escaping @MainActor () -> Void
    ) -> some View {
        task(id: isRestoring) {
            guard isRestoring else { return }
            do { try await Task.sleep(for: delay) } catch { return }
            onTimeout()
        }
    }
}
