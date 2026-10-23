import AppKit

/// O que é verdade no instante em que um painel perde o teclado.
///
/// Um valor, e não perguntas feitas ao AppKit dentro da decisão: assim a regra abaixo pode ser lida e testada
/// sem servidor de janelas.
struct PanelDismissContext: Equatable {
    /// Se o usuário quer que um clique fora feche este painel.
    var closesOnOutsideClick: Bool
    /// Já saiu da tela (pelo Esc, ou por uma ação que terminou): não há o que fechar.
    var isPanelVisible: Bool
    /// Uma folha que o próprio painel abriu. O usuário ainda está trabalhando no painel, não longe dele.
    var hasAttachedSheet: Bool
    /// Uma janela do próprio painel pegou o teclado.
    var keyWindowBelongsToPanel: Bool
    /// O seletor de cores, o de salvar, o de abrir: painéis do sistema que o conteúdo do painel chama.
    var keyWindowIsSystemPanel: Bool
}

/// Fecha um painel flutuante quando o usuário clica fora dele.
///
/// A regra é estreita de propósito. Perder o teclado não é o mesmo que ser clicado para longe: uma folha, o seletor
/// de cores e o painel de salvar tomam o teclado enquanto o usuário continua dentro do trabalho do painel.
/// Todo o resto (outro app, outra janela, a mesa) é um clique fora.
@MainActor
final class PanelDismissMonitor: NSObject, NSWindowDelegate {
    private let isEnabled: @MainActor () -> Bool
    private let dismiss: @MainActor () -> Void

    /// - Parameter isEnabled: perguntado no instante do clique e nunca guardado, para que a preferência valha
    ///   já no clique seguinte.
    init(
        isEnabled: @escaping @MainActor () -> Bool,
        dismiss: @escaping @MainActor () -> Void
    ) {
        self.isEnabled = isEnabled
        self.dismiss = dismiss
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let panel = notification.object as? NSWindow else { return }
        // Perguntado uma volta depois, de propósito: enquanto uma janela deixa de ser a principal, a que pegou o
        // teclado ainda não é a key, e não haveria com o que comparar.
        Task { @MainActor [weak self] in
            guard let self else { return }
            let keyWindow = NSApplication.shared.keyWindow
            let context = PanelDismissContext(
                closesOnOutsideClick: isEnabled(),
                isPanelVisible: panel.isVisible && !panel.isKeyWindow,
                hasAttachedSheet: panel.attachedSheet != nil,
                keyWindowBelongsToPanel: Self.belongs(keyWindow, to: panel),
                keyWindowIsSystemPanel: Self.isSystemPanel(keyWindow)
            )
            guard Self.shouldDismiss(context) else { return }
            dismiss()
        }
    }

    /// O único lugar onde a regra mora.
    static func shouldDismiss(_ context: PanelDismissContext) -> Bool {
        guard context.closesOnOutsideClick else { return false }
        guard context.isPanelVisible else { return false }
        guard !context.hasAttachedSheet else { return false }
        guard !context.keyWindowBelongsToPanel else { return false }
        return !context.keyWindowIsSystemPanel
    }

    private static func belongs(_ window: NSWindow?, to panel: NSWindow) -> Bool {
        guard let window else { return false }
        if window === panel { return true }
        if window === panel.attachedSheet { return true }
        return panel.childWindows?.contains { $0 === window } == true
    }

    private static func isSystemPanel(_ window: NSWindow?) -> Bool {
        window is NSColorPanel || window is NSSavePanel || window is NSFontPanel
    }
}
