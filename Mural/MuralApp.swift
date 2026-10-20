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

/// Onde o mural é gravado. Os testes de interface usam uma pasta própria.
enum LaunchConfiguration {
    /// `-uiTesting`: começa do mural de exemplo, apagando a pasta de testes.
    /// `-uiTestingKeep`: reabre a pasta de testes sem apagar (teste de persistência).
    static func store(arguments: [String] = ProcessInfo.processInfo.arguments) -> BoardStore {
        let base = BoardStore.defaultDirectory()
        guard arguments.contains("-uiTesting") || arguments.contains("-uiTestingKeep") else {
            return BoardStore(directory: base)
        }
        let testDirectory = base.deletingLastPathComponent().appendingPathComponent("MuralUITests", isDirectory: true)
        if arguments.contains("-uiTesting") {
            try? FileManager.default.removeItem(at: testDirectory)
        }
        return BoardStore(directory: testDirectory)
    }
}
