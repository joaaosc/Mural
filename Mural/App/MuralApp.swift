import MuralKit
import SwiftUI

@main
struct MuralApp: App {
    /// Segura o ⌘Q até todas as janelas de mural gravarem.
    @NSApplicationDelegateAdaptor(MuralAppDelegate.self) private var appDelegate
    @State private var library: BoardLibrary
    @State private var registry: BoardSessionRegistry
    @State private var commandCoordinator: MuralCommandCoordinator
    @Environment(\.openWindow) private var openWindow

    init() {
        let library = BoardLibrary(rootDirectory: LaunchConfiguration.store().directory)
        _library = State(initialValue: library)
        _registry = State(initialValue: BoardSessionRegistry(library: library))
        _commandCoordinator = State(initialValue: MuralCommandCoordinator())
    }

    var body: some Scene {
        WindowGroup(for: BoardRoute.self) { $route in
            BoardWindowHost(route: route ?? .library, registry: registry)
                .frame(minWidth: 760, minHeight: 500)
                // Material do sistema atrás de tudo: dá profundidade ao mural e acompanha a janela
                // ativa ou inativa. O mural e as páginas o cobrem em parte (`SurfaceFill`).
                .containerBackground(Material.regular, for: .window)
                .environment(\.muralCommandCoordinator, commandCoordinator)
        }
        .environment(\.muralCommandCoordinator, commandCoordinator)
        .restorationBehavior(LaunchConfiguration.isUITesting ? .disabled : .automatic)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 800)
        .commands { MuralCommands() }
    }
}
