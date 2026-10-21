import MuralKit
import SwiftUI

@main
struct MuralApp: App {
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
                .environment(\.muralCommandCoordinator, commandCoordinator)
        }
        .environment(\.muralCommandCoordinator, commandCoordinator)
        .restorationBehavior(LaunchConfiguration.isUITesting ? .disabled : .automatic)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 800)
        .commands { MuralCommands() }
    }
}
