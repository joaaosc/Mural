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
    // Uma janela fechada não pode ser a única dona de texto que não pôde ser gravado.
    private var retainedDraftSessions: [ObjectIdentifier: BoardWindowSession] = [:]

    /// Chamado a cada sessão que se registra (toda sessão de janela se registra ao carregar, qualquer que seja quem a criou). A
    /// sincronização com o iCloud o usa para ouvir as gravações sem que a sessão a conheça. Um só ouvinte: o do controlador do app.
    var onRegister: (@MainActor (BoardWindowSession) -> Void)?

    func register(_ session: BoardWindowSession) {
        entries[ObjectIdentifier(session)] = Entry(session: session)
        onRegister?(session)
    }

    func unregister(_ session: BoardWindowSession) {
        if !session.noteDrafts.isEmpty {
            retainedDraftSessions[ObjectIdentifier(session)] = session
        } else {
            retainedDraftSessions.removeValue(forKey: ObjectIdentifier(session))
        }
        entries.removeValue(forKey: ObjectIdentifier(session))
    }

    func retainDraftsDuringClose(_ session: BoardWindowSession) {
        if !session.noteDrafts.isEmpty { retainedDraftSessions[ObjectIdentifier(session)] = session }
    }

    var retainedDrafts: [BoardWindowSession] {
        retainedDraftSessions.values.sorted { $0.title < $1.title }
    }

    var sessionsWithUnwrittenDrafts: [BoardWindowSession] {
        let open = live
        let openIDs = Set(open.map(ObjectIdentifier.init))
        return (open + retainedDrafts.filter { !openIDs.contains(ObjectIdentifier($0)) })
            .filter { !$0.noteDrafts.isEmpty }
    }

    var unwrittenDraftText: String? {
        let texts = sessionsWithUnwrittenDrafts.compactMap { session in
            session.allNoteDraftText.map { "\(session.title)\n\n\($0)" }
        }
        return texts.isEmpty ? nil : texts.joined(separator: "\n\n---\n\n")
    }

    struct DraftSnapshot: Equatable {
        let drafts: [ObjectIdentifier: [UUID: NoteDraft]]
    }

    var draftSnapshot: DraftSnapshot {
        DraftSnapshot(
            drafts: Dictionary(
                uniqueKeysWithValues: sessionsWithUnwrittenDrafts.map {
                    (ObjectIdentifier($0), $0.noteDrafts)
                }))
    }

    var closedDraftSnapshot: DraftSnapshot {
        let openIDs = Set(live.map(ObjectIdentifier.init))
        return DraftSnapshot(
            drafts: Dictionary(
                uniqueKeysWithValues:
                    retainedDrafts
                    .filter { !openIDs.contains(ObjectIdentifier($0)) && !$0.noteDrafts.isEmpty }
                    .map { (ObjectIdentifier($0), $0.noteDrafts) }))
    }

    func discardRetainedDrafts(_ snapshot: DraftSnapshot) {
        let current = closedDraftSnapshot
        for (id, drafts) in snapshot.drafts where current.drafts[id] == drafts {
            retainedDraftSessions.removeValue(forKey: id)
        }
    }

    func reviewRetainedDrafts() {
        let snapshot = closedDraftSnapshot
        guard !snapshot.drafts.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "Nenhum rascunho de janela fechada"
            alert.informativeText = "Os rascunhos das janelas abertas aparecem no próprio mural."
            alert.runModal()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Rascunhos de janelas fechadas"
        alert.informativeText = "Há rascunhos que não puderam ser gravados. Eles ficam disponíveis somente enquanto o Mural estiver aberto."
        alert.addButton(withTitle: "Copiar Tudo")
        alert.addButton(withTitle: "Fechar")
        alert.addButton(withTitle: "Descartar…")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let text = retainedDrafts.filter { snapshot.drafts[ObjectIdentifier($0)] == $0.noteDrafts }.compactMap { session in
                session.allNoteDraftText.map { "\(session.title)\n\n\($0)" }
            }.joined(separator: "\n\n---\n\n")
            NSPasteboard.general.clearContents()
            if text.isEmpty || !NSPasteboard.general.setString(text, forType: .string) {
                Self.showCopyFailure()
            }
        case .alertThirdButtonReturn:
            let confirmation = NSAlert()
            confirmation.alertStyle = .warning
            confirmation.messageText = "Descartar os rascunhos?"
            confirmation.informativeText = "Os textos das janelas fechadas serão perdidos."
            confirmation.addButton(withTitle: "Cancelar")
            confirmation.addButton(withTitle: "Descartar")
            if confirmation.runModal() == .alertSecondButtonReturn { discardRetainedDrafts(snapshot) }
        default: break
        }
    }

    static func showCopyFailure() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Não foi possível copiar os rascunhos"
        alert.informativeText = "Os rascunhos continuam disponíveis enquanto o Mural estiver aberto."
        alert.runModal()
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
        return sessions.filter { !finished || $0.isDirty || !$0.noteDrafts.isEmpty }.map(\.title)
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
    var confirmQuitWithDrafts: @MainActor (String?) -> Bool = MuralAppDelegate.askAboutDrafts
    /// O editor de texto: com texto nele, sair pergunta antes, porque o texto só está na memória.
    var textEditor = TextEditorSession.shared
    /// Pergunta se descarta o texto do editor para sair. `true` sai.
    var confirmQuitWithEditorText: @MainActor () -> Bool = MuralAppDelegate.askToDiscardEditorText
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
        if textEditor.shouldAskBeforeQuit, !confirmQuitWithEditorText() { return .terminateCancel }
        guard !openSessions.live.isEmpty || !openSessions.retainedDrafts.isEmpty else { return .terminateNow }
        guard !isTerminating else { return .terminateLater }
        isTerminating = true
        Task { @MainActor in
            defer { isTerminating = false }
            let unsaved = await openSessions.flushAll(timeout: flushTimeout)
            while true {
                let snapshot = openSessions.draftSnapshot
                if !snapshot.drafts.isEmpty && !confirmQuitWithDrafts(openSessions.unwrittenDraftText) {
                    reply(false)
                    return
                }
                if !unsaved.isEmpty && !confirmQuitWithUnsavedBoards(unsaved) {
                    reply(false)
                    return
                }
                if snapshot == openSessions.draftSnapshot {
                    reply(true)
                    return
                }
            }
        }
        return .terminateLater
    }

    private static func askAboutDrafts(_ text: String?) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Há rascunhos que não foram gravados"
        alert.informativeText =
            "Os textos estão somente na memória e serão perdidos se o Mural for encerrado. Copie e revise antes de sair."
        alert.addButton(withTitle: "Cancelar")
        alert.addButton(withTitle: "Copiar e Revisar")
        alert.addButton(withTitle: "Sair e Perder Rascunhos")
        switch alert.runModal() {
        case .alertSecondButtonReturn:
            if let text {
                NSPasteboard.general.clearContents()
                if !NSPasteboard.general.setString(text, forType: .string) {
                    OpenBoardSessions.showCopyFailure()
                }
            } else {
                OpenBoardSessions.showCopyFailure()
            }
            return false
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    private static func askToDiscardEditorText() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Descartar o texto?"
        alert.informativeText = "O texto do editor só está na memória e será perdido se o Mural for encerrado."
        alert.addButton(withTitle: "Cancelar")
        alert.addButton(withTitle: "Descartar")
        return alert.runModal() == .alertSecondButtonReturn
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
