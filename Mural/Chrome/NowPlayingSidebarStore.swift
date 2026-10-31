import Foundation
import Observation

/// Se a pessoa levou o miniplayer para a barra lateral de murais.
///
/// Lido das preferências ao criar (sem nada guardado, o miniplayer não está na barra lateral) e gravado a cada mudança. Nos
/// testes de interface a leitura é ignorada, para um teste não herdar o lugar do anterior; `-uiTestingKeep` volta a ler, para
/// testar a persistência. Nesse caso as preferências são as de um conjunto próprio dos testes, que não mexe nas do app.
@MainActor
@Observable
final class NowPlayingSidebarStore {
    static let shared = NowPlayingSidebarStore()

    /// A chave das preferências.
    static let key = "nowPlayingInSidebar"

    /// O miniplayer foi levado para a barra lateral: a cápsula flutuante só aparece quando a barra lateral está fechada.
    var isInSidebar: Bool {
        didSet {
            guard isInSidebar != oldValue else { return }
            preferences.set(isInSidebar, forKey: Self.key)
        }
    }

    private let preferences: UserDefaults

    init(
        preferences: UserDefaults = NowPlayingSidebarStore.defaultPreferences(),
        readsStoredValue: Bool = NowPlayingSidebarStore.readsStoredValueByDefault
    ) {
        self.preferences = preferences
        isInSidebar = readsStoredValue ? preferences.bool(forKey: Self.key) : false
    }

    static func defaultPreferences() -> UserDefaults {
        guard LaunchConfiguration.isUITesting else { return .standard }
        return UserDefaults(suiteName: "com.joaocosta.Mural.uitests") ?? .standard
    }

    static var readsStoredValueByDefault: Bool {
        !LaunchConfiguration.isUITesting || ProcessInfo.processInfo.arguments.contains("-uiTestingKeep")
    }
}
