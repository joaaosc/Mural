import AppKit
import Foundation
import MuralKit
import Observation

/// Uma aba da janela: um mural aberto e a sessão que o apresenta.
struct BoardTab: Identifiable {
    let id: UUID
    let session: BoardWindowSession
    /// Nome conhecido antes de o mural carregar (lista de murais ou aba restaurada).
    var placeholderTitle: String?

    var route: BoardRoute { session.route }
    var boardID: BoardID { session.boardID }

    /// O nome do mural; enquanto ele carrega, o nome que já se sabia.
    @MainActor var title: String {
        session.model != nil ? session.title : (placeholderTitle ?? session.title)
    }
}

/// Pedidos que a janela atende com uma folha ou um painel do sistema.
enum MuralWindowRequest: Equatable, Sendable {
    case newBoard
    case openPackage
}

/// As abas abertas e o que se lembra delas entre aberturas do app.
struct MuralTabsSnapshot: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var route: BoardRoute
        var title: String
    }

    var entries: [Entry]
    var selectedIndex: Int?

    /// Texto guardado pela janela (`@SceneStorage`); vazio ou ilegível vira `nil`.
    init?(storage: String) {
        guard let data = storage.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(Self.self, from: data)
        else { return nil }
        self = decoded
    }

    init(entries: [Entry], selectedIndex: Int?) {
        self.entries = entries
        self.selectedIndex = selectedIndex
    }

    var storage: String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// As abas da janela do Mural, como no Safari: uma aba por mural aberto, e um mural em uma aba só.
///
/// Vive no app, não numa view: os menus (⌘N, ⌘W, ⌃⇥) e o Dock agem sobre ela mesmo sem janela. As abas
/// que saem da frente continuam carregadas; trocar de aba pausa a apresentação de uma e retoma a da
/// outra, sem reler o disco.
@MainActor
@Observable
final class MuralTabs {
    let registry: BoardSessionRegistry

    private(set) var tabs: [BoardTab] = []
    private(set) var selectedID: UUID?
    /// Barra lateral com todos os murais; sem abas, ela fica aberta.
    var isSidebarVisible = false
    /// Pedido esperando a janela (que pode ainda não existir).
    var request: MuralWindowRequest?
    /// Há um rascunho de exemplo para retomar.
    private(set) var resumeDraftAvailable = false
    /// Muda quando a lista de murais pode ter mudado: a barra lateral relê.
    private(set) var libraryRevision = 0

    /// A janela do Mural. Uma segunda janela que apareça entrega a vez a esta.
    @ObservationIgnored private(set) weak var window: NSWindow?
    /// Abre a janela quando não há nenhuma (ação do SwiftUI registrada pelos menus).
    @ObservationIgnored var openMainWindow: (@MainActor () -> Void)?
    @ObservationIgnored private let makeSession: @MainActor (BoardRoute) -> BoardWindowSession
    /// Uma folha (nome, ⌘V, painel de arquivos, confirmação) está aberta na janela.
    @ObservationIgnored var isShowingSheet: @MainActor () -> Bool = { false }
    @ObservationIgnored var closeWindow: @MainActor () -> Void = {}
    @ObservationIgnored private var loadStarted: Set<UUID> = []

    init(
        registry: BoardSessionRegistry,
        makeSession: (@MainActor (BoardRoute) -> BoardWindowSession)? = nil
    ) {
        self.registry = registry
        self.makeSession = makeSession ?? { BoardWindowSession(route: $0, registry: registry) }
        self.isShowingSheet = { [weak self] in self?.window?.attachedSheet != nil }
        self.closeWindow = { [weak self] in self?.window?.performClose(nil) }
    }

    var selected: BoardTab? {
        tabs.first { $0.id == selectedID }
    }

    func tab(for boardID: BoardID) -> BoardTab? {
        tabs.first { $0.boardID == boardID }
    }

    // MARK: Abrir, trocar e fechar

    /// Abre o mural numa aba nova à direita da ativa, ou vai para a aba dele se já estiver aberto.
    @discardableResult
    func open(_ route: BoardRoute, title: String? = nil) -> BoardTab? {
        guard let boardID = Self.boardID(of: route) else { return nil }
        if let existing = tab(for: boardID) {
            select(existing.id)
            return existing
        }
        let tab = BoardTab(id: UUID(), session: makeSession(route), placeholderTitle: title)
        let index = tabs.firstIndex { $0.id == selectedID }.map { $0 + 1 } ?? tabs.endIndex
        tabs.insert(tab, at: index)
        activate(tab)
        libraryRevision &+= 1
        return tab
    }

    /// Vai para outra aba. Recusado com uma folha aberta: o painel perderia a resposta.
    @discardableResult
    func select(_ id: UUID) -> Bool {
        guard id != selectedID else { return true }
        guard let tab = tabs.first(where: { $0.id == id }), !isShowingSheet() else { return false }
        activate(tab)
        return true
    }

    func selectNext() { selectNeighbor(offset: 1) }
    func selectPrevious() { selectNeighbor(offset: -1) }

    /// Fecha a aba e grava o mural dela; a vizinha da direita (ou da esquerda) assume. Sem abas, fecha a janela.
    func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        if id == selectedID, isShowingSheet() { return }
        let closing = tabs.remove(at: index)
        loadStarted.remove(closing.id)
        if id == selectedID {
            selectedID = nil
            if let next = tabs.indices.contains(index) ? tabs[index] : tabs.last {
                activate(next)
            }
        }
        libraryRevision &+= 1
        Task { await closing.session.handleWindowWillClose() }
        if tabs.isEmpty {
            isSidebarVisible = true
            closeWindow()
        }
    }

    func closeSelected() {
        if let selectedID {
            close(selectedID)
        } else {
            closeWindow()
        }
    }

    func closeOthers(_ id: UUID) {
        for tab in tabs where tab.id != id {
            close(tab.id)
        }
    }

    /// A janela está fechando: grava e encerra todos os murais abertos.
    func closeAll() async {
        let closing = tabs
        tabs = []
        selectedID = nil
        loadStarted = []
        libraryRevision &+= 1
        // Uma tarefa por mural: as gravações avançam juntas, cada uma na sua fila.
        let closes = closing.map { tab in Task { await tab.session.handleWindowWillClose() } }
        for close in closes { await close.value }
    }

    /// Rascunho promovido a mural salvo: a aba continua no mesmo lugar, com a rota nova.
    func replace(_ id: UUID, with route: BoardRoute) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), Self.boardID(of: route) != nil else { return }
        let old = tabs[index]
        let tab = BoardTab(id: UUID(), session: makeSession(route), placeholderTitle: old.title)
        tabs[index] = tab
        loadStarted.remove(old.id)
        if selectedID == old.id {
            selectedID = nil
            activate(tab)
        }
        libraryRevision &+= 1
        Task { await old.session.handleWindowWillClose() }
    }

    /// A aba que tinha a sessão (o `RootView` conhece a sessão, não a aba).
    func tabID(of session: BoardWindowSession) -> UUID? {
        tabs.first { $0.session === session }?.id
    }

    /// Mural renomeado, criado ou importado: a barra lateral relê a lista.
    func libraryDidChange() {
        libraryRevision &+= 1
    }

    // MARK: Janela

    /// Registra a janela que apareceu. Devolve `false` se já existe outra: a nova deve se fechar.
    func attach(_ newWindow: NSWindow) -> Bool {
        if let window, window !== newWindow, window.isVisible || window.isMiniaturized {
            return false
        }
        window = newWindow
        return true
    }

    /// A janela principal fechou; as abas são encerradas por `closeAll()`.
    func detachWindow() {
        window = nil
    }

    /// Traz a janela para a frente ou, sem janela, abre uma.
    func showWindow() {
        if let window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        } else {
            openMainWindow?()
        }
    }

    /// Visualizar › Mostrar Todos os Murais: a janela com a barra lateral aberta.
    func showAllMurals() {
        isSidebarVisible = true
        showWindow()
    }

    func requestNewBoard() {
        request = .newBoard
        showWindow()
    }

    func requestOpenPackage() {
        request = .openPackage
        showWindow()
    }

    // MARK: Biblioteca

    /// Cria o mural com o nome dado (vazio vira "Mural sem título") e o abre numa aba.
    func createBoard(named value: String) async throws {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = name.isEmpty ? "Mural sem título" : name
        let route = try await registry.library.createNamedBoard(title)
        open(route, title: title)
    }

    func refreshDraftAvailability() async {
        resumeDraftAvailable = (try? await registry.library.lifecycleState())?.lifecycle == .draft
    }

    /// Arquivo › Retomar Rascunho de Exemplo: abre o rascunho, se ele ainda for rascunho.
    func resumeDraft() async {
        guard let state = try? await registry.library.lifecycleState(), state.lifecycle == .draft else {
            resumeDraftAvailable = false
            return
        }
        resumeDraftAvailable = true
        open(.welcomeDraft(state.stableWelcomeID))
        showWindow()
    }

    // MARK: Restauração

    var snapshot: MuralTabsSnapshot {
        MuralTabsSnapshot(
            entries: tabs.map { .init(route: $0.route, title: $0.title) },
            selectedIndex: tabs.firstIndex { $0.id == selectedID })
    }

    /// Reabre as abas guardadas pela janela, sem repetir mural nem a rota da biblioteca. Só a aba ativa
    /// carrega agora; as outras carregam quando forem escolhidas.
    func restore(_ snapshot: MuralTabsSnapshot) {
        guard tabs.isEmpty else { return }
        let selectedRoute = snapshot.selectedIndex.flatMap {
            snapshot.entries.indices.contains($0) ? snapshot.entries[$0].route : nil
        }
        var seen: Set<BoardID> = []
        for entry in snapshot.entries {
            guard let boardID = Self.boardID(of: entry.route), seen.insert(boardID).inserted else { continue }
            tabs.append(BoardTab(id: UUID(), session: makeSession(entry.route), placeholderTitle: entry.title))
        }
        guard let first = tabs.first else { return }
        activate(tabs.first { $0.route == selectedRoute } ?? first)
        libraryRevision &+= 1
    }

    // MARK: Interno

    /// Pausa a aba que sai e mostra a que entra (carregando-a na primeira vez).
    private func activate(_ tab: BoardTab) {
        if let current = selected, current.id != tab.id {
            current.session.suspendPresentation()
        }
        selectedID = tab.id
        if loadStarted.insert(tab.id).inserted {
            let session = tab.session
            Task { await session.load() }
        } else {
            tab.session.resumePresentation()
        }
    }

    private func selectNeighbor(offset: Int) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == selectedID }) else { return }
        let next = (index + offset + tabs.count) % tabs.count
        select(tabs[next].id)
    }

    private static func boardID(of route: BoardRoute) -> BoardID? {
        switch route {
        case .library: nil
        case .welcomeDraft(let id), .saved(let id): id
        }
    }
}
