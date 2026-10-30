import MuralKit
import SwiftUI
import os

@main
struct MuralApp: App {
    /// Segura o ⌘Q até todas as abas de mural gravarem.
    @NSApplicationDelegateAdaptor(MuralAppDelegate.self) private var appDelegate
    @State private var tabs: MuralTabs
    /// O Live Share. Existe com o iCloud de verdade e, só em desenvolvimento, na demonstração (`-uiTesting -liveShareDemo`).
    @State private var liveShare: LiveShareController?
    /// As cópias dos murais na pasta Mural do iCloud Drive. Existe com o entitlement do iCloud Drive; os Ajustes o recebem daqui.
    @State private var driveMirror: DriveMirrorController?

    private static let log = Logger(subsystem: "com.joaocosta.Mural", category: "Sincronização")

    init() {
        LaunchConfiguration.preparePerformanceFixtureIfRequested()
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
        // O Live Share depende dela: só existe com ela ligada.
        let cloudMode = LaunchConfiguration.cloudSync()
        var live: LiveShareController?
        var syncController: CloudSyncController?
        if cloudMode != .off {
            // Com o iCloud de verdade, o estado fica na pasta do ambiente desta cópia (desenvolvimento ou produção): as duas cópias
            // não dividem o estado, e os murais acompanhados na outra não vão para o Lixo. Sem a pasta, `Sync`, como sempre foi.
            let location = cloudMode == .cloudKit ? Self.syncLocation() : nil
            let sync: CloudSyncController
            if let location {
                sync = CloudSyncController(mode: cloudMode, registry: registry, delivery: delivery, directory: location.directory)
            } else {
                sync = CloudSyncController(mode: cloudMode, registry: registry, delivery: delivery)
            }
            CloudSyncController.current = sync
            let isOtherEnvironment = location?.isOtherEnvironment ?? false
            Task {
                await sync.start()
                if isOtherEnvironment { await sync.reportBoardsFromAnotherEnvironment() }
            }
            live = Self.makeLiveShare(mode: cloudMode, sync: sync, tabs: tabs)
            syncController = sync
        }
        _liveShare = State(initialValue: live)

        // As cópias dos murais na pasta Mural do iCloud Drive. As gravações locais vêm do controlador do iCloud, as exclusões e a
        // lista de murais, das abas. Sem o entitlement do iCloud Drive (e nos testes) não existe: o app se comporta como sempre.
        var mirror: DriveMirrorController?
        if LaunchConfiguration.mirrorsToICloudDrive() {
            let controller = DriveMirrorController(
                library: library, awaitingFirstFetch: { [weak syncController] in syncController?.boardsAwaitingFirstFetch ?? [] },
                renameBoard: { [weak tabs, delivery] id, name in
                    // Mesmo caminho do nome que chega do iCloud: a sessão do mural (aberto ou não) grava, e a cópia o segue.
                    let renamed = try? await delivery.withSession(for: .saved(id)) { session, _ in
                        await session.rename(to: name)
                        return session.manifestName == name
                    }
                    guard renamed == true else { return false }
                    tabs?.libraryDidChange()
                    return true
                })
            syncController?.onLocalSave = { controller.boardChanged($0) }
            tabs.onBoardDeletedByUser = { controller.boardDeletedByUser($0) }
            tabs.onLibraryChanged = { controller.libraryChanged() }
            controller.start()
            mirror = controller
        }
        _driveMirror = State(initialValue: mirror)

        // Os testes de interface não leem nem sobrescrevem a área de transferência da pessoa. O painel usa uma área
        // nomeada e limpa, que cada teste pode preencher com dados próprios.
        let panelPasteboard: NSPasteboard
        let panelClipboardReader: ClipboardReader
        if LaunchConfiguration.isUITesting {
            panelPasteboard = NSPasteboard(name: NSPasteboard.Name("com.joaocosta.Mural.UITests.Clipboard"))
            panelPasteboard.clearContents()
            panelClipboardReader = ClipboardReader(pasteboard: panelPasteboard, accessBehavior: { _ in .ask })
        } else {
            panelPasteboard = .general
            panelClipboardReader = ClipboardReader()
        }

        // O painel de vidro que o ícone da barra de menus abre. O conteúdo é montado a cada apresentação, com um modelo
        // novo: a lista e o mural do centro nascem do instante em que o painel abre.
        MenuBarController.shared.install { _ in
            let model = MenuBarPanelModel(
                library: library, covers: coverService, activeBoard: { tabs.selected?.boardID },
                reader: panelClipboardReader, delivery: delivery)
            return GlassHostingView(
                rootView: MenuBarPanelView(
                    tabs: tabs,
                    model: model,
                    playback: .shared,
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

    /// A pasta do estado de sincronização do ambiente desta cópia (`SyncLocation`) e se ela é a do outro ambiente. `nil` se a marca não
    /// pôde ser lida nem gravada: o controlador usa então `Sync`, como antes da separação.
    private static func syncLocation() -> (directory: URL, isOtherEnvironment: Bool)? {
        do {
            return try SyncLocation.resolve(root: LaunchConfiguration.libraryRoot(), environment: CloudAvailability.currentEnvironment)
        } catch {
            log.error("Pasta do estado por ambiente não resolvida: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// O Live Share do app. Com o iCloud de verdade, passa a receber as sessões do SharePlay. No iCloud falso dos testes de interface
    /// só existe na demonstração (`-liveShareDemo`, só em desenvolvimento), que começa sem chamada do FaceTime e não escuta o sistema.
    /// Sem iCloud, não existe.
    private static func makeLiveShare(mode: CloudSyncMode, sync: CloudSyncController, tabs: MuralTabs) -> LiveShareController? {
        switch mode {
        case .off:
            return nil
        case .cloudKit:
            let live = LiveShareController(sync: sync, tabs: tabs)
            live.listen()
            return live
        case .inMemory:
            #if DEBUG
            guard LaunchConfiguration.isLiveShareDemo() else { return nil }
            let demo = LiveShareDemoStarter(tabs: tabs)
            let live = LiveShareController(sync: sync, tabs: tabs, starter: demo)
            demo.controller = live
            return live
            #else
            return nil
            #endif
        }
    }

    var body: some Scene {
        // Uma janela só, com as abas dentro dela. `WindowGroup`, e não `Window`: com `Window` como cena
        // principal, o app sairia ao fechar a janela.
        WindowGroup(id: MuralWindowView.sceneID) {
            MuralWindowView(tabs: tabs)
                // O Live Share para as telas que o leem; `nil` sem ele.
                .environment(liveShare)
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
            MuralSettingsView(driveMirror: driveMirror)
        }
    }
}
