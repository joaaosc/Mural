import AppKit
import Foundation

/// Uma cópia do Mural aberta, resumida ao que decide quem fica com o ícone da barra de menus.
nonisolated struct RunningMural: Equatable, Sendable {
    let processID: pid_t
    let launchDate: Date?
    let bundleURL: URL?
}

/// Qual cópia do Mural mostra o ícone da barra de menus quando há mais de uma aberta (o app instalado e uma cópia de
/// desenvolvimento ou de teste têm o mesmo identificador).
nonisolated enum MenuBarIconOwnership {
    /// O processo que fica com o ícone, ou `nil` sem nenhum Mural aberto.
    ///
    /// A ordem: o instalado antes das cópias de outros lugares (DerivedData, uma pasta de testes); entre iguais, o que abriu
    /// primeiro (sem data vai para o fim); no empate, o menor `processID`. É uma ordem total sobre dados que toda cópia lê do
    /// mesmo jeito, e por isso as cópias chegam à mesma resposta sem conversar entre si.
    static func owner(among running: [RunningMural]) -> pid_t? {
        running.min(by: isPreferred)?.processID
    }

    /// O `.app` está numa pasta chamada `Applications` (`/Applications` ou `~/Applications`)?
    static func isInstalled(_ bundleURL: URL?) -> Bool {
        bundleURL?.deletingLastPathComponent().lastPathComponent == "Applications"
    }

    /// `lhs` vem antes de `rhs` na ordem de preferência.
    private static func isPreferred(_ lhs: RunningMural, over rhs: RunningMural) -> Bool {
        let lhsInstalled = isInstalled(lhs.bundleURL)
        let rhsInstalled = isInstalled(rhs.bundleURL)
        if lhsInstalled != rhsInstalled { return lhsInstalled }

        switch (lhs.launchDate, rhs.launchDate) {
        case (let lhsDate?, let rhsDate?) where lhsDate != rhsDate: return lhsDate < rhsDate
        case (.some, .none): return true
        case (.none, .some): return false
        default: break
        }
        return lhs.processID < rhs.processID
    }
}

/// Deixa o ícone da barra de menus só na cópia que é a dona dele, e passa o ícone adiante quando ela fecha.
///
/// Cada cópia avalia por conta própria, toda vez que uma cópia abre ou fecha, com a mesma regra (`MenuBarIconOwnership`):
/// a dona mostra o ícone e as outras o escondem. Quando a dona fecha, a que sobra reavalia e assume.
@MainActor
final class MenuBarIconCoordinator {
    static let shared = MenuBarIconCoordinator()

    private let bundleIdentifier: String
    private let processID: pid_t
    private let notificationCenter: NotificationCenter
    private let runningMurals: @MainActor () -> [RunningMural]
    private let setIconVisible: @MainActor (Bool) -> Void
    private var observers: [any NSObjectProtocol] = []

    /// - Parameters:
    ///   - bundleIdentifier: o identificador das cópias que disputam o ícone; só avisos dele reavaliam.
    ///   - processID: o processo desta cópia.
    ///   - notificationCenter: de onde vêm os avisos de aplicativo aberto e fechado.
    ///   - runningMurals: as cópias abertas agora; por padrão, o que o sistema diz (`systemMurals(bundleIdentifier:)`).
    ///   - setIconVisible: mostra ou esconde o ícone desta cópia.
    init(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.joaocosta.Mural",
        processID: pid_t = getpid(),
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        runningMurals: (@MainActor () -> [RunningMural])? = nil,
        setIconVisible: @escaping @MainActor (Bool) -> Void = { MenuBarController.shared.setStatusItemVisible($0) }
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.processID = processID
        self.notificationCenter = notificationCenter
        self.runningMurals = runningMurals ?? { Self.systemMurals(bundleIdentifier: bundleIdentifier) }
        self.setIconVisible = setIconVisible
    }

    /// Decide agora e passa a reavaliar sempre que uma cópia do Mural abre ou fecha. Uma segunda chamada só reavalia.
    func start() {
        if observers.isEmpty {
            observers = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification].map { name in
                notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                    // Só valores simples passam para o ator principal: `Notification` não é `Sendable`.
                    let identifier = Self.bundleIdentifier(of: notification)
                    let ended = Self.endedProcessID(of: notification)
                    MainActor.assumeIsolated { self?.handleApplication(withBundleIdentifier: identifier, excluding: ended) }
                }
            }
        }
        evaluate()
    }

    /// Mostra o ícone se esta cópia é a dona dele; senão, o esconde.
    func evaluate(excluding ended: pid_t? = nil) {
        // O aviso de término pode chegar antes de a lista do sistema esquecer a cópia que fechou: ela não conta mais.
        let running = runningMurals().filter { $0.processID != ended }
        setIconVisible(MenuBarIconOwnership.owner(among: running) == processID)
    }

    /// Um aplicativo abriu ou fechou: reavalia se for uma cópia do Mural (outra ou esta).
    func handle(_ notification: Notification) {
        handleApplication(withBundleIdentifier: Self.bundleIdentifier(of: notification), excluding: Self.endedProcessID(of: notification))
    }

    private func handleApplication(withBundleIdentifier identifier: String?, excluding ended: pid_t?) {
        guard identifier == bundleIdentifier else { return }
        evaluate(excluding: ended)
    }

    private nonisolated static func bundleIdentifier(of notification: Notification) -> String? {
        (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
    }

    /// O processo que acabou de fechar, num aviso de término; `nil` nos outros avisos.
    private nonisolated static func endedProcessID(of notification: Notification) -> pid_t? {
        guard notification.name == NSWorkspace.didTerminateApplicationNotification else { return nil }
        return (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
    }

    /// As cópias do Mural abertas agora, segundo o sistema, mais esta cópia se o sistema ainda não a listar (logo depois de
    /// abrir) e sem as que já terminaram.
    static func systemMurals(bundleIdentifier: String) -> [RunningMural] {
        var applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { !$0.isTerminated }
        let current = NSRunningApplication.current
        if !applications.contains(where: { $0.processIdentifier == current.processIdentifier }) {
            applications.append(current)
        }
        return applications.map {
            RunningMural(processID: $0.processIdentifier, launchDate: $0.launchDate, bundleURL: $0.bundleURL)
        }
    }
}
