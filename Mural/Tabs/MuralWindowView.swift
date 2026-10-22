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
    @State private var detailWidth: CGFloat = 800
    @State private var isNewBoardPresented = false
    @State private var boardNameDraft = ""
    @State private var isPackageImporterPresented = false
    @State private var alert: WindowAlert?

    private enum WindowRole {
        case pending, primary, extra
    }

    /// Espaço da barra da janela que não é da faixa de abas: semáforos e botão da barra lateral à
    /// esquerda (só eles ficam no detalhe quando a barra lateral está fechada) e o "+" à direita.
    private var stripWidth: CGFloat {
        let leading: CGFloat = tabs.isSidebarVisible ? 60 : 150
        return max(0, detailWidth - leading - 70)
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { tabs.isSidebarVisible ? .all : .detailOnly },
            set: { tabs.isSidebarVisible = $0 != .detailOnly })
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

    private var window: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            MuralsSidebar(tabs: tabs)
        } detail: {
            detail
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: {
                    detailWidth = $0
                }
        }
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .principal) {
                BoardTabStrip(tabs: tabs, width: stripWidth)
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .primaryAction) {
                Button("Novo mural", systemImage: "plus") { tabs.requestNewBoard() }
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
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
        .onChange(of: tabs.request) { _, _ in consumeRequest() }
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
        }
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

/// Aviso simples da janela (criar ou importar um mural).
private struct WindowAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
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
