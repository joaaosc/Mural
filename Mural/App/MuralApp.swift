import MuralKit
import SwiftUI

@main
struct MuralApp: App {
    /// Segura o ⌘Q até todas as abas de mural gravarem.
    @NSApplicationDelegateAdaptor(MuralAppDelegate.self) private var appDelegate
    @State private var tabs: MuralTabs

    init() {
        // Nos testes de interface, o mural excluído é apagado em vez de ir para o Lixo de quem roda os testes.
        let discard: @Sendable (URL) throws -> Void
        if LaunchConfiguration.isUITesting {
            discard = { url in try FileManager.default.removeItem(at: url) }
        } else {
            discard = { url in try BoardLibrary.moveToTrash(url) }
        }
        let library = BoardLibrary(rootDirectory: LaunchConfiguration.store().directory, discardPackage: discard)
        let tabs = MuralTabs(registry: BoardSessionRegistry(library: library))
        _tabs = State(initialValue: tabs)

        // O ícone na barra de menus e o painel de vidro que ele abre. O conteúdo é montado a cada apresentação.
        MenuBarController.shared.install { _ in
            GlassHostingView(
                rootView: MenuBarPanelView(
                    tabs: tabs,
                    close: { MenuBarController.shared.dismiss() },
                    resize: { MenuBarController.shared.fitToContent() }
                )
                .panelGlassSurface()
            )
        }
    }

    var body: some Scene {
        // Uma janela só, com as abas dentro dela. `WindowGroup`, e não `Window`: com `Window` como cena
        // principal, o app sairia ao fechar a janela.
        WindowGroup(id: MuralWindowView.sceneID) {
            MuralWindowView(tabs: tabs)
                // Material fino do sistema atrás de tudo: o mural deixa ver o que está atrás da janela, como
                // vidro, e acompanha a janela ativa ou inativa. O mural e as páginas o cobrem em parte (`SurfaceFill`).
                .containerBackground(Material.thin, for: .window)
        }
        .restorationBehavior(LaunchConfiguration.isUITesting ? .disabled : .automatic)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 800)
        .commands {
            MuralCommands(tabs: tabs)
        }
    }
}
