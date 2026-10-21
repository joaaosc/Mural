import MuralKit
import SwiftUI

@main
struct MuralApp: App {
    @State private var library: BoardLibrary
    @State private var registry: BoardSessionRegistry

    init() {
        let library = BoardLibrary(rootDirectory: LaunchConfiguration.store().directory)
        _library = State(initialValue: library)
        _registry = State(initialValue: BoardSessionRegistry(library: library))
    }

    var body: some Scene {
        WindowGroup(for: BoardRoute.self) { $route in
            BoardWindowHost(route: route ?? .library, registry: registry)
                .frame(minWidth: 760, minHeight: 500)
        }
        .restorationBehavior(LaunchConfiguration.isUITesting ? .disabled : .automatic)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 800)
        .commands { MuralCommands() }
    }
}
