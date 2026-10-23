import AppKit
import MuralKit

/// Abre um item de música no app Música; sem o app, no navegador.
@MainActor
enum MusicOpener {
    static let bundleIdentifier = "com.apple.Music"

    /// O que fazer, decidido sem abrir nada.
    enum Target: Equatable {
        /// Abre o endereço no app Música.
        case urlInMusicApp(URL, app: URL)
        /// Só abre o app Música.
        case musicApp(URL)
        /// Sem o app, abre o endereço no navegador.
        case browser(URL)
        case nothing
    }

    static func target(for music: MusicSnapshot, musicAppURL: URL?) -> Target {
        switch (music.url, musicAppURL) {
        case (let url?, let app?): .urlInMusicApp(url, app: app)
        case (nil, let app?): .musicApp(app)
        case (let url?, nil): .browser(url)
        case (nil, nil): .nothing
        }
    }

    static func open(_ music: MusicSnapshot) {
        let workspace = NSWorkspace.shared
        let appURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        switch target(for: music, musicAppURL: appURL) {
        case .urlInMusicApp(let url, let app):
            workspace.open([url], withApplicationAt: app, configuration: configuration)
        case .musicApp(let app):
            workspace.openApplication(at: app, configuration: configuration)
        case .browser(let url):
            workspace.open(url)
        case .nothing:
            break
        }
    }
}
