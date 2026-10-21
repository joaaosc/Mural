import Foundation

/// Quando buscar a prévia de um link e quanto esperar antes de tentar de novo.
public enum LinkPreviewPolicy {
    /// Espera depois da primeira falha.
    public static let baseRetryDelay: TimeInterval = 60 * 60
    /// Teto da espera entre tentativas: 7 dias.
    public static let maximumRetryDelay: TimeInterval = 7 * 24 * 60 * 60

    /// Indica se a prévia deve ser buscada agora: sempre se está pendente, nunca se já está pronta e,
    /// se falhou, só depois de `retryDelay(afterAttempts:)` desde a última tentativa.
    ///
    /// Uma falha datada no futuro (relógio do sistema que andou para trás) não bloqueia a nova tentativa.
    public static func shouldFetch(_ state: LinkPreviewState, now: Date) -> Bool {
        switch state {
        case .pending:
            return true
        case .ready:
            return false
        case .failed(let failedAt, let attempts):
            let elapsed = now.timeIntervalSince(failedAt)
            return elapsed < 0 || elapsed >= retryDelay(afterAttempts: attempts)
        }
    }

    /// Espera depois de `attempts` falhas seguidas: 1 h, 2 h, 4 h... dobrando a cada falha, no máximo 7 dias.
    /// Menos de uma falha conta como uma.
    public static func retryDelay(afterAttempts attempts: Int) -> TimeInterval {
        // Acima de 20 dobras o teto já foi passado há muito; limitar o expoente evita estouro.
        let doublings = min(max(attempts, 1) - 1, 20)
        return min(baseRetryDelay * Double(1 << doublings), maximumRetryDelay)
    }
}
