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
        let registry = BoardSessionRegistry(library: library)

        // As capas da vitrine do painel. Um serviço só para o app inteiro: ele guarda as imagens na memória entre uma
        // abertura do painel e outra. `libraryRoot()` só calcula o endereço; `store()` apagaria a pasta dos testes de
        // interface.
        let coverService = BoardCoverService(
            library: library,
            files: BoardCoverFiles(
                directory: LaunchConfiguration.libraryRoot().appendingPathComponent("BoardCovers", isDirectory: true)),
            liveBoards: {
                OpenBoardSessions.shared.live.compactMap { session in
                    guard !session.isClosed, let model = session.model else { return nil }
                    return LiveBoard(id: session.boardID, model: model)
                }
            },
            linkPreviewFiles: { LinkPreviewFiles(directory: LaunchConfiguration.linkPreviewsDirectory(for: $0)) }
        )

        // A entrega do que foi copiado a um mural escolhido no painel. As abas adotam a sessão que a entrega abriu para
        // um mural fechado: nunca existem duas sessões do mesmo mural. O painel da barra de menus cola por ela.
        let delivery = BoardDelivery(registry: registry, covers: coverService)
        let tabs = MuralTabs(
            registry: registry,
            makeSession: { route in
                delivery.adoptDetachedSession(for: route) ?? BoardWindowSession(route: route, registry: registry)
            })
        delivery.tabs = tabs
        _tabs = State(initialValue: tabs)

        // A sincronização com o iCloud. Sem o entitlement de CloudKit e fora dos testes de interface ela fica desligada: nenhum
        // controlador, nenhum motor, e o app se comporta como sempre. O delegado do app (buscar ao ativar) o encontra em `current`.
        let cloudMode = LaunchConfiguration.cloudSync()
        if cloudMode != .off {
            let sync = CloudSyncController(mode: cloudMode, registry: registry, delivery: delivery)
            CloudSyncController.current = sync
            Task { await sync.start() }
        }

        // O painel de vidro que o ícone da barra de menus abre. O conteúdo é montado a cada apresentação, com um modelo
        // novo: a lista e o mural do centro nascem do instante em que o painel abre.
        MenuBarController.shared.install { _ in
            let model = MenuBarPanelModel(
                library: library, covers: coverService, activeBoard: { tabs.selected?.boardID },
                reader: ClipboardReader(), delivery: delivery)
            return GlassHostingView(
                rootView: MenuBarPanelView(
                    tabs: tabs,
                    model: model,
                    close: { MenuBarController.shared.dismiss() },
                    resize: { MenuBarController.shared.fitToContent() },
                    moved: { MenuBarController.shared.panelWasMoved() }
                )
                .panelGlassSurface()
            )
        }
        // O atalho global abre e fecha o mesmo painel. Fica pronto antes de o coordenador do ícone decidir a dona, que é
        // quem o registra.
        PanelHotKeyCenter.shared.start { MenuBarController.shared.toggleFromShortcut() }
        // Com duas cópias abertas (a instalada e uma de desenvolvimento ou de teste), só uma mostra o ícone (e responde ao
        // atalho); a outra assume quando ela fecha.
        MenuBarIconCoordinator.shared.start()
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
        // A janela não abre sozinha no lançamento (a restauração do macOS continua): quem a abre é o delegate, que sabe se
        // o app foi aberto pelo início de sessão, quando ele fica só na barra de menus.
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(LaunchConfiguration.isUITesting ? .disabled : .automatic)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 800)
        .commands {
            MuralCommands(tabs: tabs)
        }

        // Mural › Ajustes… (⌘,) e a engrenagem do painel da barra de menus abrem esta janela.
        Settings {
            MuralSettingsView()
        }
    }
}
