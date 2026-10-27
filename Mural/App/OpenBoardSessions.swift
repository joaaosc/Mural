import AppKit
import CloudKit
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

    /// Chamado a cada sessão que se registra (toda sessão de janela se registra ao carregar, qualquer que seja quem a criou). A
    /// sincronização com o iCloud o usa para ouvir as gravações sem que a sessão a conheça. Um só ouvinte: o do controlador do app.
    var onRegister: (@MainActor (BoardWindowSession) -> Void)?

    func register(_ session: BoardWindowSession) {
        entries[ObjectIdentifier(session)] = Entry(session: session)
        onRegister?(session)
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

/// Abre a janela do Mural de fora de uma view: o delegate do app não tem `openWindow`.
/// `MuralCommands`, que existe mesmo sem janelas, registra aqui a ação do SwiftUI.
@MainActor
final class MainWindowOpener {
    static let shared = MainWindowOpener()

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

/// Segura o término do app até as janelas de mural gravarem e abre a janela quando o app é aberto,
/// menos pelo início de sessão: aí o app fica só na barra de menus, sem janela e fora do Dock.
@MainActor
final class MuralAppDelegate: NSObject, NSApplicationDelegate {
    var openSessions = OpenBoardSessions.shared
    var windowOpener = MainWindowOpener.shared
    var flushTimeout: Duration = .seconds(10)
    /// Espera a restauração de janelas do macOS antes de conferir se alguma abriu.
    var launchWindowCheckDelay: Duration = .milliseconds(800)
    /// O evento de Apple que abriu o app; trocado nos testes para simular o início de sessão.
    var currentAppleEvent: @MainActor () -> NSAppleEventDescriptor? = { NSAppleEventManager.shared().currentAppleEvent }
    /// Avisa o Dock: `false` sem janela de mural (o app fica só na barra de menus), `true` com ela.
    var dockPresence: @MainActor (Bool) -> Void = { $0 ? DockPresence.windowDidAppear() : DockPresence.noWindow() }
    /// Resposta ao AppKit; trocada nos testes para não encerrar o processo de teste.
    var reply: @MainActor (Bool) -> Void = { NSApp.reply(toApplicationShouldTerminate: $0) }
    /// Pergunta o que fazer quando algo não foi salvo. `true` sai mesmo assim.
    var confirmQuitWithUnsavedBoards: @MainActor ([String]) -> Bool = MuralAppDelegate.askToQuitAnyway
    /// Há alguma janela do app aberta (inclusive minimizada)?
    var hasOpenWindow: @MainActor () -> Bool = {
        NSApp.windows.contains { ($0.isVisible || $0.isMiniaturized) && $0.canBecomeMain }
    }
    /// O controlador da sincronização com o iCloud; `nil` com ela desligada (então o app não faz nada a mais por causa dela).
    var cloudSync: @MainActor () -> CloudSyncController? = { CloudSyncController.current }
    private var isTerminating = false

    /// As abas são do próprio app (`MuralWindowView`), como no Safari: sem isso, com a preferência do
    /// sistema "Preferir abas: sempre", o macOS juntaria janelas numa barra de abas própria.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    /// A cena do mural não abre a janela sozinha no lançamento (`.defaultLaunchBehavior(.suppressed)`), e o estado
    /// salvo pode não ter nenhuma janela restaurável (sessões de teste, janelas fechadas). Depois da restauração, sem
    /// nenhuma janela, abre a janela com a lista de murais.
    ///
    /// Aberto pelo início de sessão, não abre: o Mural fica só com o ícone da barra de menus e sai do Dock. Se a
    /// restauração do macOS já trouxe uma janela, o Dock fica como está, porque há janela.
    func applicationDidFinishLaunching(_ notification: Notification) {
        // O iCloud de verdade avisa por notificação remota quando o que está lá muda. O iCloud falso não envia nenhuma.
        if cloudSync()?.mode == .cloudKit { NSApplication.shared.registerForRemoteNotifications() }
        if LaunchContext.isLoginItemLaunch(currentAppleEvent()) {
            if !hasOpenWindow() { dockPresence(false) }
            return
        }
        let delay = launchWindowCheckDelay
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            openWindowIfNeeded()
        }
    }

    /// A pessoa pode ter mudado "Abrir ao Iniciar Sessão" nos Ajustes do Sistema enquanto o app estava em segundo
    /// plano: o item do menu do app relê o estado ao voltar.
    ///
    /// Ao ativar o app, busca também o que mudou no iCloud enquanto ele estava em segundo plano (sem sincronização, nada).
    func applicationDidBecomeActive(_ notification: Notification) {
        LoginItemModel.shared.refresh()
        guard let sync = cloudSync() else { return }
        Task { @MainActor in await sync.fetch() }
    }

    /// O iCloud avisou que há mudança: busca.
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        guard let sync = cloudSync() else { return }
        Task { @MainActor in await sync.fetch() }
    }

    /// A pessoa abriu o link de um convite do iCloud: o controlador o aceita e abre o mural numa aba (sem sincronização, nada).
    func application(_ application: NSApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        guard let sync = cloudSync() else { return }
        Task { @MainActor in await sync.acceptShare(metadata) }
    }

    /// Clique no ícone do Dock sem janelas abertas, ou abrir o app pelo Finder ou pelo Spotlight enquanto ele roda só
    /// na barra de menus: abre a janela.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag, !hasOpenWindow() else { return true }
        return !windowOpener.open()
    }

    func openWindowIfNeeded() {
        guard !hasOpenWindow() else { return }
        windowOpener.open()
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
