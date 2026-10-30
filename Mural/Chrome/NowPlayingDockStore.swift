import Foundation
import Observation

/// Onde a pessoa deixou o miniplayer da última vez: esquerda, centro ou direita do rodapé.
///
/// Lido das preferências ao criar (valor que não é um ponto conhecido vale como esquerda) e gravado a cada mudança. Nos
/// testes de interface a leitura é ignorada, para um teste não herdar o lugar do anterior; `-uiTestingKeep` volta a ler, para
/// testar a persistência. Nesse caso as preferências são as de um conjunto próprio dos testes, que não mexe nas do app.
@MainActor
@Observable
final class NowPlayingDockStore {
    static let shared = NowPlayingDockStore()

    /// A chave das preferências.
    static let key = "nowPlayingBarDock"

    var dock: NowPlayingDock {
        didSet {
            guard dock != oldValue else { return }
            preferences.set(dock.rawValue, forKey: Self.key)
        }
    }

    private let preferences: UserDefaults

    init(
        preferences: UserDefaults = NowPlayingDockStore.defaultPreferences(),
        readsStoredValue: Bool = NowPlayingDockStore.readsStoredValueByDefault
    ) {
        self.preferences = preferences
        dock =
            readsStoredValue
            ? preferences.string(forKey: Self.key).flatMap(NowPlayingDock.init(rawValue:)) ?? .leading
            : .leading
    }

    static func defaultPreferences() -> UserDefaults {
        guard LaunchConfiguration.isUITesting else { return .standard }
        return UserDefaults(suiteName: "com.joaocosta.Mural.uitests") ?? .standard
    }

    static var readsStoredValueByDefault: Bool {
        !LaunchConfiguration.isUITesting || ProcessInfo.processInfo.arguments.contains("-uiTestingKeep")
    }
}
