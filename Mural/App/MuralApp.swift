import MuralKit
import SwiftUI

@main
struct MuralApp: App {
    @State private var model = BoardModel(store: LaunchConfiguration.store())
    @State private var commands = AppCommandsState()

    var body: some Scene {
        Window("Mural", id: "board") {
            RootView(model: model, commands: commands)
                .frame(minWidth: 760, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Importar…") { commands.isImporterPresented = true }
                    .keyboardShortcut("o")
            }
        }
    }
}
