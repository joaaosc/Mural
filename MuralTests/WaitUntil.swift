import Testing

/// Espera a condição ficar verdadeira, consultando a cada 5 ms; registra uma falha se passar de `timeout`.
func waitUntil(
    _ description: String, timeout: Duration = .seconds(10), sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () async -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while await !condition() {
        if clock.now >= deadline {
            Issue.record("Tempo esgotado esperando: \(description)", sourceLocation: sourceLocation)
            return
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
}
