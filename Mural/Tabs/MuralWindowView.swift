import AppKit
import MuralKit
import SwiftUI

/// A janela do Mural, como a do Safari no layout compacto: abas na mesma linha dos botões da janela,
/// o botão da barra lateral (todos os murais) ao lado dos semáforos e "+" para um mural novo.
///
/// O app tem uma janela só. Uma segunda que apareça (por exemplo, restaurada de uma versão em que cada
/// mural tinha a sua) não mostra nada, entrega a vez à primeira e se fecha.
struct MuralWindowView: View {
    /// Identificador da cena da janela (`openWindow(id:)`).
    static let sceneID = "main"

    let tabs: MuralTabs

    /// Abas abertas e aba ativa, para reabrir junto com a janela (segue a preferência do sistema).
    @SceneStorage("mural.tabs") private var storedTabs = ""
    @SceneStorage("mural.sidebar") private var storedSidebar = false
    @State private var role = WindowRole.pending
    @State private var windowWidth: CGFloat = 1240
    /// Onde o item da faixa começa na janela, medido: o item central da barra não fica no centro exato.
    @State private var stripOriginX: CGFloat = 0
    @State private var isNewBoardPresented = false
    @State private var boardNameDraft = ""
    @State private var isPackageImporterPresented = false
    /// O popover do botão Compartilhar está aberto (pelo botão ou por Arquivo › Compartilhar…).
    @State private var isSharePresented = false
    @State private var alert: WindowAlert?

    private enum WindowRole {
        case pending, primary, extra
    }

    /// Largura do item da faixa na barra da janela: tudo menos os semáforos e o botão da barra lateral à
    /// esquerda, o botão Compartilhar (quando o mural da aba pode ser compartilhado) e o "+" à direita. Um item
    /// da barra não estica sozinho; ele usa a largura pedida.
    private var stripItemWidth: CGFloat {
        max(0, windowWidth - 150 - 70 - (tabs.shareTarget == nil ? 0 : ShareToolbarControl.toolbarWidth))
    }

    /// Com a barra lateral aberta, as abas começam depois dela (e da linha divisória), como no Safari. A conta
    /// usa a posição medida do item, e não uma estimativa dos botões à esquerda.
    private var stripLeadingInset: CGFloat {
        guard tabs.isSidebarVisible else { return 0 }
        return max(0, MuralsSidebar.width + 1 + BoardTabStrip.sidebarGap - stripOriginX)
    }

    var body: some View {
        Group {
            if role == .primary {
                window
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 760, minHeight: 500)
        .background {
            WindowLifecycleObserver(onAttach: attach) {
                guard role == .primary else { return }
                tabs.detachWindow()
                Task { await tabs.closeAll() }
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    /// Barra lateral e mural lado a lado numa view só, e não num `NavigationSplitView`: dentro da coluna de
    /// conteúdo dele, o mural não recebe o teclado ao aparecer, e o ⌘V logo depois de abrir não chegaria.
    private var window: some View {
        HStack(spacing: 0) {
            if tabs.isSidebarVisible {
                MuralsSidebar(tabs: tabs)
                    .transition(.move(edge: .leading))
                Divider()
                    .ignoresSafeArea()
            }
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.smooth(duration: 0.25), value: tabs.isSidebarVisible)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            windowWidth = $0
        }
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Murais", systemImage: "sidebar.left") { tabs.isSidebarVisible.toggle() }
                    .help(tabs.isSidebarVisible ? "Ocultar os murais (⌃⌘S)" : "Mostrar todos os murais (⌃⌘S)")
                    .accessibilityIdentifier("murals-sidebar-button")
            }
            ToolbarItem(placement: .principal) {
                BoardTabStrip(tabs: tabs, width: stripItemWidth - stripLeadingInset)
                    .padding(.leading, stripLeadingInset)
                    .onGeometryChange(for: CGFloat.self) {
                        $0.frame(in: .global).minX
                    } action: {
                        stripOriginX = $0
                    }
            }
            // O vidro do sistema cobriria também o recuo sobre a barra lateral: a faixa desenha o próprio vidro.
            .sharedBackgroundVisibility(.hidden)
            // O botão Compartilhar tem a cápsula de vidro própria: o espaço fixo o separa da cápsula do "+".
            if let target = tabs.shareTarget {
                ToolbarItem(placement: .primaryAction) {
                    ShareToolbarControl(tab: target.tab, tabs: tabs, sync: target.sync, isPresented: $isSharePresented)
                }
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Novo mural", systemImage: "plus", action: tabs.requestNewBoard)
                    .help("Novo mural (⌘N)")
                    .accessibilityIdentifier("new-board-button")
            }
        }
        .environment(tabs)
        .sheet(isPresented: $isNewBoardPresented) {
            NewBoardSheet(name: $boardNameDraft, onCancel: { isNewBoardPresented = false }, onCreate: createBoard)
        }
        .fileImporter(
            isPresented: $isPackageImporterPresented,
            allowedContentTypes: [.muralPackage],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let source = urls.first else { return }
            importPackage(from: source)
        }
        .alert(
            alert?.title ?? "",
            isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } }),
            presenting: alert
        ) { alert in
            // Aviso do iCloud: o OK o dispensa. Os outros alertas ficam com o botão padrão. O aviso de falta de acesso ao Live Share
            // traz o convite e oferece pedir acesso ao dono do mural.
            if let noticeID = alert.noticeID {
                if let url = alert.requestAccessURL {
                    Button("Pedir Acesso") {
                        CloudSyncController.current?.dismissNotice(noticeID)
                        Task { await CloudSyncController.current?.requestAccess(to: url) }
                    }
                    Button("Agora Não", role: .cancel) { CloudSyncController.current?.dismissNotice(noticeID) }
                } else {
                    Button("OK") { CloudSyncController.current?.dismissNotice(noticeID) }
                }
            }
        } message: { alert in
            Text(alert.message)
        }
        .confirmationDialog(
            tabs.deletionRequest?.title ?? "",
            isPresented: Binding(
                get: { tabs.deletionRequest != nil }, set: { if !$0 { tabs.deletionRequest = nil } }),
            titleVisibility: .visible,
            presenting: tabs.deletionRequest
        ) { request in
            Button(request.confirmTitle, role: request.isDestructive ? .destructive : nil) { delete(request) }
            Button("Cancelar", role: .cancel) {}
        } message: { request in
            Text(request.message)
        }
        .onChange(of: tabs.request) { _, _ in consumeRequest() }
        // O popover é do mural da aba: trocar de aba, ou o botão perder o sentido (mural excluído, ainda carregando), o fecha.
        .onChange(of: tabs.selectedID) { _, _ in isSharePresented = false }
        .onChange(of: tabs.canShareSelected) { _, canShare in if !canShare { isSharePresented = false } }
        // Os avisos de murais que saíram do iCloud usam o alerta da janela, um de cada vez.
        .onChange(of: CloudSyncController.current?.notices, initial: true) { _, _ in presentNextNotice() }
        .onChange(of: alert?.id) { _, id in if id == nil { presentNextNotice() } }
        .onChange(of: tabs.snapshot) { _, snapshot in storedTabs = snapshot.storage }
        .onChange(of: tabs.isSidebarVisible) { _, visible in storedSidebar = visible }
        .onOpenURL { source in
            guard source.pathExtension.lowercased() == "mural" else { return }
            importPackage(from: source)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let tab = tabs.selected {
            BoardTabContent(tab: tab, tabs: tabs)
                .id(tab.id)
        } else {
            ContentUnavailableView {
                Label("Nenhum mural aberto", systemImage: "rectangle.on.rectangle")
            } description: {
                Text("Escolha um mural na barra lateral ou crie um novo.")
            } actions: {
                Button("Novo mural") { tabs.requestNewBoard() }
            }
        }
    }

    // MARK: Janela única

    private func attach(_ window: NSWindow) {
        // Fora da atualização da view: o AppKit avisa no meio da montagem da janela.
        Task { @MainActor in
            guard role == .pending else { return }
            guard tabs.attach(window) else {
                role = .extra
                tabs.showWindow()
                window.close()
                return
            }
            role = .primary
            if tabs.tabs.isEmpty {
                if let snapshot = MuralTabsSnapshot(storage: storedTabs), !snapshot.entries.isEmpty {
                    tabs.restore(snapshot)
                    tabs.isSidebarVisible = storedSidebar
                } else {
                    tabs.isSidebarVisible = true
                }
            }
            consumeRequest()
        }
    }

    // MARK: Novo mural e importação

    private func consumeRequest() {
        guard role == .primary, let request = tabs.request else { return }
        tabs.request = nil
        switch request {
        case .newBoard:
            boardNameDraft = ""
            isNewBoardPresented = true
        case .openPackage:
            isPackageImporterPresented = true
        case .share(let route):
            // O pedido vale para a aba que estava ativa ao pedir; quem trocou de aba nesse meio-tempo não vê o popover de outro mural.
            isSharePresented = tabs.selected?.route == route && tabs.canShareSelected
        }
    }

    /// Mostra o aviso mais antigo do iCloud quando a janela não tem outro alerta na frente.
    private func presentNextNotice() {
        guard alert == nil, let notice = CloudSyncController.current?.notices.first else { return }
        alert = WindowAlert(
            title: notice.title, message: notice.message, noticeID: notice.id, requestAccessURL: notice.requestAccessURL)
    }

    private func createBoard() {
        isNewBoardPresented = false
        let name = boardNameDraft
        Task {
            do {
                try await tabs.createBoard(named: name)
            } catch {
                alert = WindowAlert(
                    title: "Não foi possível criar o mural", message: error.localizedDescription)
            }
        }
    }

    /// Faz o que o diálogo confirmou (excluir, sair do mural recebido ou tirar do iCloud); o erro vira o alerta da janela.
    private func delete(_ request: BoardDeletionRequest) {
        tabs.deletionRequest = nil
        Task {
            do {
                try await tabs.perform(request)
            } catch {
                alert = WindowAlert(title: request.failureTitle, message: error.localizedDescription)
            }
        }
    }

    private func importPackage(from source: URL) {
        Task {
            do {
                let library = tabs.registry.library
                let result = try await MuralPackageImport.importAsCopy(from: source, using: library)
                let name = try await library.open(result.route)?.manifest.name ?? "Mural"
                tabs.open(result.route, title: name)
                tabs.libraryDidChange()
                alert = WindowAlert(
                    title: "Importação concluída",
                    message: "Mural ‘\(name)’ importado como uma cópia interna. O arquivo original não será alterado."
                        + Self.workspaceNotice(for: result.workspaceStatus))
            } catch {
                alert = WindowAlert(title: "Não foi possível importar o mural", message: error.localizedDescription)
            }
        }
    }

    private static func workspaceNotice(for status: BoardPortableWorkspaceStatus) -> String {
        switch status {
        case .loaded:
            return ""
        case .missing:
            return " O estado visual estava ausente; a visualização padrão foi usada."
        case .corrupted(let filename):
            return " O estado visual estava corrompido (\(filename)); a visualização padrão foi usada."
        case .futureSchema(let version):
            return " O estado visual usa uma versão futura (\(version)); a visualização padrão foi usada."
        }
    }
}

/// Aviso simples da janela (criar ou importar um mural, ou um aviso do iCloud).
private struct WindowAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    /// O aviso do iCloud que este alerta mostra; `nil` nos demais.
    var noticeID: UUID?
    /// O convite cujo acesso a pessoa pode pedir ao dono (o aviso de falta de acesso ao Live Share); `nil` nos demais.
    var requestAccessURL: URL?
}

/// O conteúdo de uma aba: o mural, ou o carregamento, ou o erro com as saídas possíveis.
private struct BoardTabContent: View {
    let tab: BoardTab
    let tabs: MuralTabs

    var body: some View {
        let session = tab.session
        Group {
            if session.model != nil {
                RootView(session: session)
            } else if let error = session.error {
                ContentUnavailableView {
                    Label("Mural indisponível", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Tentar de novo") { Task { await session.retryLoad() } }
                    Button("Fechar aba") { tabs.close(tab.id) }
                }
            } else {
                ProgressView("Abrindo mural…")
            }
        }
        .navigationTitle(tab.title)
    }
}

/// Folha "Novo mural": o nome e Criar (vazio vira "Mural sem título").
private struct NewBoardSheet: View {
    @Binding var name: String
    var onCancel: () -> Void
    var onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Novo mural").font(.headline)
            TextField("Nome do mural", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onCreate)
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel, action: onCancel)
                Button("Criar", action: onCreate)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
