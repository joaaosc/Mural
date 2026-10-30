import AppKit

/// Quem abre a cópia de edição no app escolhido. Os testes usam uma versão que não abre nada.
protocol PasteEditorLaunching: Sendable {
    /// Abre o arquivo no app e traz o app para a frente.
    /// - Throws: o erro do sistema quando o app não abre o arquivo.
    func open(_ file: URL, with application: URL) async throws
}

/// Abre de verdade, pelo `NSWorkspace`: o app vai para a frente e o arquivo não entra nos documentos recentes.
struct WorkspaceEditorLauncher: PasteEditorLaunching {
    func open(_ file: URL, with application: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.addsToRecentItems = false
            // O app aberto (`NSRunningApplication`) não é `Sendable`: só o resultado atravessa.
            NSWorkspace.shared.open([file], withApplicationAt: application, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

/// Para os testes de interface: não abre nada. Simula a pessoa editando um texto, acrescentando " (editado)" ao fim do
/// arquivo (uma vez só); os outros tipos ficam como estão.
struct FixtureEditorLauncher: PasteEditorLaunching {
    static let suffix = " (editado)"

    func open(_ file: URL, with application: URL) async throws {
        guard file.pathExtension == "txt" else { return }
        let text = try String(contentsOf: file, encoding: .utf8)
        guard !text.hasSuffix(Self.suffix) else { return }
        try Data((text + Self.suffix).utf8).write(to: file)
    }
}
