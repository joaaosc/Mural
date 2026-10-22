import AppKit
import Foundation

/// Janelas de mural abertas, para que sair do app (⌘Q, logout, reinício) espere a
/// gravação de todas. Guarda referências fracas: uma janela fechada sai sozinha.
@MainActor
final class OpenBoardSessions {
    static let shared = OpenBoardSessions()

    private struct Entry {
        weak var session: BoardWindowSession?
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    func register(_ session: BoardWindowSession) {
        entries[ObjectIdentifier(session)] = Entry(session: session)
    }

    func unregister(_ session: BoardWindowSession) {
        entries.removeValue(forKey: ObjectIdentifier(session))
    }

    var live: [BoardWindowSession] {
        entries.values.compactMap(\.session)
    }

    /// Grava todas as janelas abertas e devolve os títulos que não puderam ser salvos
    /// dentro do prazo (falha de gravação ou gravação ainda presa).
    func flushAll(timeout: Duration) async -> [String] {
        let sessions = live
        guard !sessions.isEmpty else { return [] }
        let flush = Task { @MainActor in
            // Uma tarefa por janela: as gravações avançam juntas, cada uma na sua fila.
            let flushes = sessions.map { session in
                Task { @MainActor in await session.flushAndPrepareToLeave() }
            }
            for flush in flushes { await flush.value }
        }
        let finished = await Self.wait(for: flush, timeout: timeout)
        return sessions.filter { !finished || $0.isDirty }.map(\.title)
    }

    /// Espera a tarefa ou o prazo, o que vier primeiro, sem esperar a tarefa depois do prazo.
    private static func wait(for task: Task<Void, Never>, timeout: Duration) async -> Bool {
        let gate = OnceGate()
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                await task.value
                if gate.open() { continuation.resume(returning: true) }
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                if gate.open() { continuation.resume(returning: false) }
            }
        }
    }
}

@MainActor
private final class OnceGate {
    private var isOpen = true

    /// Devolve `true` só na primeira chamada.
    func open() -> Bool {
        guard isOpen else { return false }
        isOpen = false
        return true
    }
}

/// Abre a biblioteca de fora de uma view: o delegate do app não tem `openWindow`.
/// `MuralCommands`, que existe mesmo sem janelas, registra aqui a ação do SwiftUI.
@MainActor
final class LibraryWindowOpener {
    static let shared = LibraryWindowOpener()

    private var action: (@MainActor () -> Void)?

    func register(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    /// Devolve `false` quando ainda não há ação registrada.
    @discardableResult
    func open() -> Bool {
        guard let action else { return false }
        action()
        return true
    }
}

/// Segura o término do app até as janelas de mural gravarem e garante que o app nunca
/// fique aberto sem nenhuma janela.
@MainActor
final class MuralAppDelegate: NSObject, NSApplicationDelegate {
    var openSessions = OpenBoardSessions.shared
    var libraryOpener = LibraryWindowOpener.shared
    var flushTimeout: Duration = .seconds(10)
    /// Espera a restauração de janelas do macOS antes de conferir se alguma abriu.
    var launchWindowCheckDelay: Duration = .milliseconds(800)
    /// Resposta ao AppKit; trocada nos testes para não encerrar o processo de teste.
    var reply: @MainActor (Bool) -> Void = { NSApp.reply(toApplicationShouldTerminate: $0) }
    /// Pergunta o que fazer quando algo não foi salvo. `true` sai mesmo assim.
    var confirmQuitWithUnsavedBoards: @MainActor ([String]) -> Bool = MuralAppDelegate.askToQuitAnyway
    /// Há alguma janela do app aberta (inclusive minimizada)?
    var hasOpenWindow: @MainActor () -> Bool = {
        NSApp.windows.contains { ($0.isVisible || $0.isMiniaturized) && $0.canBecomeMain }
    }
    private var isTerminating = false

    /// O estado salvo pode dizer que havia janelas sem nenhuma restaurável (sessões de teste,
    /// janelas fechadas): o macOS então não cria a janela padrão e o app abre só com a
    /// barra de menus. Depois da restauração, sem nenhuma janela, abre a biblioteca.
    func applicationDidFinishLaunching(_ notification: Notification) {
        let delay = launchWindowCheckDelay
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            openLibraryIfNoWindow()
        }
    }

    /// Clique no ícone do Dock sem janelas abertas: abre a biblioteca.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag, !hasOpenWindow() else { return true }
        return !libraryOpener.open()
    }

    func openLibraryIfNoWindow() {
        guard !hasOpenWindow() else { return }
        libraryOpener.open()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !openSessions.live.isEmpty else { return .terminateNow }
        guard !isTerminating else { return .terminateLater }
        isTerminating = true
        Task { @MainActor in
            let unsaved = await openSessions.flushAll(timeout: flushTimeout)
            isTerminating = false
            reply(unsaved.isEmpty || confirmQuitWithUnsavedBoards(unsaved))
        }
        return .terminateLater
    }

    private static func askToQuitAnyway(_ titles: [String]) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Não foi possível salvar todas as alterações"
        alert.informativeText =
            "Alterações em \(titles.joined(separator: ", ")) ainda não foram gravadas. "
            + "Sair agora pode perder essas alterações."
        alert.addButton(withTitle: "Cancelar")
        alert.addButton(withTitle: "Sair Mesmo Assim")
        return alert.runModal() == .alertSecondButtonReturn
    }
}
