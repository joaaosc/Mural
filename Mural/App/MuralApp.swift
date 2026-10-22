import MuralKit
import SwiftUI

@main
struct MuralApp: App {
    /// Segura o ⌘Q até todas as abas de mural gravarem.
    @NSApplicationDelegateAdaptor(MuralAppDelegate.self) private var appDelegate
    @State private var tabs: MuralTabs

    init() {
        let library = BoardLibrary(rootDirectory: LaunchConfiguration.store().directory)
        _tabs = State(initialValue: MuralTabs(registry: BoardSessionRegistry(library: library)))
    }

    var body: some Scene {
        // Uma janela só, com as abas dentro dela. `WindowGroup`, e não `Window`: com `Window` como cena
        // principal, o app sairia ao fechar a janela.
        WindowGroup(id: MuralWindowView.sceneID) {
            MuralWindowView(tabs: tabs)
                // Material do sistema atrás de tudo: dá profundidade ao mural e acompanha a janela
                // ativa ou inativa. O mural e as páginas o cobrem em parte (`SurfaceFill`).
                .containerBackground(Material.regular, for: .window)
        }
        .restorationBehavior(LaunchConfiguration.isUITesting ? .disabled : .automatic)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 800)
        .commands {
            MuralCommands(tabs: tabs)
            SidebarCommands()
        }
    }
}
