import AppKit
import Foundation
import MuralKit
import MuralSync
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
    /// Abre o popover do botão Compartilhar para o mural da aba (Arquivo › Compartilhar…).
    case share(BoardRoute)
}

/// Pedido de excluir um mural, à espera da confirmação na janela.
struct BoardDeletionRequest: Identifiable, Equatable, Sendable {
    /// O que a confirmação faz, conforme o papel da pessoa no mural (o `cloud` do manifesto).
    enum Kind: Equatable, Sendable {
        /// Mural só deste Mac (ou o rascunho de exemplo): vai para o Lixo.
        case local
        /// Mural do dono no iCloud: sai do iCloud e de todos os Macs dele. `participants` são os convidados que já aceitaram.
        case everywhere(participants: Int)
        /// Mural recebido por convite: a pessoa sai dele, e quem compartilhou continua com o mural.
        case leave
        /// Mural do dono no iCloud que fica só neste Mac (não é uma exclusão, mas passa pela mesma confirmação).
        case removeFromICloud(participants: Int)
    }

    let route: BoardRoute
    let name: String
    var kind: Kind = .local

    var id: BoardRoute { route }
    var isDraft: Bool { route.isDraft }

    /// O rótulo do item de menu que pede a exclusão, conforme o papel da pessoa no mural (`MuralTabs.role(for:)`).
    static func menuTitle(role: BoardCloudInfo.Database?) -> String {
        role == .shared ? "Sair do Mural Compartilhado…" : "Excluir Mural…"
    }

    /// O título do diálogo de confirmação.
    var title: String {
        switch kind {
        case .local: "Excluir “\(name)”?"
        case .everywhere: "Excluir “\(name)” em todos os seus Macs?"
        case .leave: "Sair de “\(name)”?"
        case .removeFromICloud: "Tirar “\(name)” do iCloud?"
        }
    }

    /// A mensagem do diálogo de confirmação.
    var message: String {
        switch kind {
        case .local:
            isDraft
                ? "O rascunho de exemplo será descartado e não poderá ser recuperado."
                : "O mural e os arquivos guardados nele vão para o Lixo do Mac."
        case .everywhere(let participants):
            "O mural sai do iCloud e de todos os seus Macs." + Self.lostAccess(participants)
        case .leave:
            "O mural sai deste Mac e você deixa de recebê-lo. Quem compartilhou continua com ele."
        case .removeFromICloud(let participants):
            "O mural continua neste Mac, mas sai dos seus outros Macs"
                + (participants == 0 ? "" : " e as pessoas convidadas perdem o acesso") + "."
        }
    }

    /// Quantas pessoas perdem o acesso, no singular ou no plural; nada quando ninguém aceitou o convite.
    private static func lostAccess(_ participants: Int) -> String {
        switch participants {
        case 0: ""
        case 1: " 1 pessoa perde o acesso."
        default: " \(participants) pessoas perdem o acesso."
        }
    }

    /// O texto do botão que confirma.
    var confirmTitle: String {
        switch kind {
        case .local: isDraft ? "Descartar" : "Mover para o Lixo"
        case .everywhere: "Excluir"
        case .leave: "Sair"
        case .removeFromICloud: "Tirar do iCloud"
        }
    }

    /// O botão que confirma é destrutivo: o mural sai deste Mac ou some do iCloud para todos. Tirar do iCloud mantém o mural aqui.
    var isDestructive: Bool {
        if case .removeFromICloud = kind { false } else { true }
    }

    /// O título do alerta se a confirmação falhar.
    var failureTitle: String {
        switch kind {
        case .local, .everywhere: "Não foi possível excluir o mural"
        case .leave: "Não foi possível sair do mural"
        case .removeFromICloud: "Não foi possível tirar o mural do iCloud"
        }
    }
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
    /// Mural a excluir, esperando a confirmação na janela.
    var deletionRequest: BoardDeletionRequest?
    /// Há um rascunho de exemplo para retomar.
    private(set) var resumeDraftAvailable = false
    /// Muda quando a lista de murais pode ter mudado: a barra lateral relê.
    private(set) var libraryRevision = 0
    /// Muda quando o mural da aba ativa deve ficar com o teclado (⌘V, Esc), por exemplo depois de um
    /// clique na barra lateral, que deixa o teclado na lista.
    private(set) var boardFocusRequest = 0

    /// A janela do Mural. Uma segunda janela que apareça entrega a vez a esta.
    @ObservationIgnored private(set) weak var window: NSWindow?
    /// Abre a janela quando não há nenhuma (ação do SwiftUI registrada pelos menus).
    @ObservationIgnored var openMainWindow: (@MainActor () -> Void)?
    /// O tocador do app; os testes trocam.
    @ObservationIgnored var musicPlayback: MusicPlayback = .shared
    @ObservationIgnored private let makeSession: @MainActor (BoardRoute) -> BoardWindowSession
    /// Uma folha (nome, ⌘V, painel de arquivos, confirmação) está aberta na janela.
    @ObservationIgnored var isShowingSheet: @MainActor () -> Bool = { false }
    @ObservationIgnored var closeWindow: @MainActor () -> Void = {}
    /// Avisa o Dock: `true` com a janela do mural na tela, `false` sem ela (o app fica só na barra de menus).
    @ObservationIgnored var dockPresence: @MainActor (Bool) -> Void = {
        $0 ? DockPresence.windowDidAppear() : DockPresence.noWindow()
    }
    /// Apaga o que o app guarda de um mural fora do pacote dele (as prévias de link).
    @ObservationIgnored var removeBoardCaches: @MainActor (BoardID) -> Void = { boardID in
        try? FileManager.default.removeItem(at: LaunchConfiguration.linkPreviewsDirectory(for: boardID))
    }
    /// O controlador da sincronização com o iCloud; `nil` com ela desligada. Os testes trocam.
    @ObservationIgnored var cloudSync: @MainActor () -> CloudSyncController? = { CloudSyncController.current }
    /// Chamado com o mural de cada aba que sai (`close`, `closeAll` e `replace`, que tira a aba antiga): o Live Share sai da sessão do
    /// mural que deixou de estar aberto. Um ouvinte só.
    @ObservationIgnored var onBoardClosed: (@MainActor (BoardID) -> Void)?
    /// Chamado com o mural que a pessoa excluiu neste Mac ("Excluir" só daqui ou em todos os Macs), depois de a exclusão terminar sem
    /// erro; nunca ao sair de mural recebido nem ao tirar do iCloud. A cópia do iCloud Drive sai junto. Um ouvinte só.
    @ObservationIgnored var onBoardDeletedByUser: (@MainActor (BoardID) -> Void)?
    /// Chamado quando a lista de murais pode ter mudado (`libraryDidChange`): as cópias do iCloud Drive conferem os nomes. Um ouvinte só.
    @ObservationIgnored var onLibraryChanged: (@MainActor () -> Void)?
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
        if id == selectedID, isShowingSheet() { return }
        guard let closing = removeTab(id) else { return }
        onBoardClosed?(closing.boardID)
        Task { await closing.session.handleWindowWillClose() }
        if tabs.isEmpty {
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
        for tab in closing { onBoardClosed?(tab.boardID) }
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
        onBoardClosed?(old.boardID)
        Task { await old.session.handleWindowWillClose() }
    }

    /// A aba que tinha a sessão (o `RootView` conhece a sessão, não a aba).
    func tabID(of session: BoardWindowSession) -> UUID? {
        tabs.first { $0.session === session }?.id
    }

    /// Abre (ou volta para) o mural, traz a janela para a frente e devolve o teclado a ele.
    func showBoard(_ route: BoardRoute, title: String?) {
        open(route, title: title)
        showWindow()
        focusBoard()
    }

    /// Devolve o teclado ao mural da aba ativa.
    func focusBoard() {
        boardFocusRequest &+= 1
    }

    /// Mural renomeado, criado ou importado: a barra lateral relê a lista.
    func libraryDidChange() {
        libraryRevision &+= 1
        onLibraryChanged?()
    }

    // MARK: Janela

    /// Registra a janela que apareceu. Devolve `false` se já existe outra: a nova deve se fechar.
    func attach(_ newWindow: NSWindow) -> Bool {
        if let window, window !== newWindow, window.isVisible || window.isMiniaturized {
            return false
        }
        window = newWindow
        dockPresence(true)
        return true
    }

    /// A janela principal fechou; as abas são encerradas por `closeAll()`. Sem janela, o app sai do Dock.
    func detachWindow() {
        window = nil
        dockPresence(false)
    }

    /// Os menus dizem como abrir a janela: só eles têm a ação do SwiftUI mesmo quando não há janela.
    func registerWindowOpener(_ open: @escaping @MainActor () -> Void) {
        openMainWindow = open
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

    /// A aba ativa e o controlador, quando o mural dela pode ser compartilhado: um mural salvo (não o rascunho de exemplo) e a
    /// sincronização ligada. O botão Compartilhar da barra, a largura da faixa de abas e o item do menu seguem esta regra.
    var shareTarget: (tab: BoardTab, sync: CloudSyncController)? {
        guard let sync = cloudSync(), sync.isEnabled, let tab = selected, case .saved = tab.route else { return nil }
        return (tab, sync)
    }

    /// O botão Compartilhar da aba ativa está habilitado: o mural já carregou, e só então se sabe se está no iCloud e com quem.
    var canShareSelected: Bool {
        shareTarget?.tab.session.model != nil
    }

    /// Arquivo › Compartilhar…: abre o popover de compartilhamento do mural da aba ativa.
    func requestShareSelected() {
        guard canShareSelected, let selected else { return }
        request = .share(selected.route)
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

    // MARK: Excluir mural

    /// O papel da pessoa num mural do iCloud, para escolher a exclusão e os rótulos dos menus: `nil` num mural só deste Mac ou com a
    /// sincronização desligada (a exclusão é então a local, mesmo que o manifesto ainda tenha `cloud`).
    func role(for cloud: BoardCloudInfo?) -> BoardCloudInfo.Database? {
        guard cloudSync()?.isEnabled == true else { return nil }
        return cloud?.database
    }

    /// Pede a confirmação para excluir o mural (a janela pergunta). O que a confirmação faz depende do papel da pessoa nele, lido do
    /// manifesto agora (a lista da barra lateral pode estar desatualizada): excluir só daqui, excluir em todos os Macs do dono ou
    /// sair de um mural recebido.
    func requestDelete(_ route: BoardRoute, name: String) async {
        guard Self.boardID(of: route) != nil else { return }
        let kind: BoardDeletionRequest.Kind
        switch await cloudRole(of: route) {
        case nil: kind = .local
        case (.shared, _)?: kind = .leave
        case (.private, let participants)?: kind = .everywhere(participants: participants)
        }
        deletionRequest = BoardDeletionRequest(route: route, name: name, kind: kind)
        showWindow()
    }

    /// Arquivo › Excluir Mural…: o mural da aba ativa.
    func requestDeleteSelected() async {
        guard let selected else { return }
        await requestDelete(selected.route, name: selected.title)
    }

    /// Pede a confirmação para tirar do iCloud o mural do dono: ele continua neste Mac e sai dos outros. Não faz nada para o mural
    /// que não é do dono no iCloud.
    func requestRemoveFromICloud(_ route: BoardRoute, name: String) async {
        guard case (.private, let participants)? = await cloudRole(of: route) else { return }
        deletionRequest = BoardDeletionRequest(route: route, name: name, kind: .removeFromICloud(participants: participants))
        showWindow()
    }

    /// Faz o que a janela confirmou, conforme o tipo do pedido.
    /// - Throws: o erro da exclusão, da saída ou da retirada do iCloud; `CloudSyncControllerError.disabled` se a sincronização foi
    ///   desligada depois do pedido.
    func perform(_ request: BoardDeletionRequest) async throws {
        guard let boardID = Self.boardID(of: request.route) else { throw BoardLibraryError.unavailableRoute(request.route) }
        switch request.kind {
        case .local:
            try await deleteBoard(request.route)
            onBoardDeletedByUser?(boardID)
        case .everywhere:
            try await enabledCloudSync().deleteEverywhere(boardID)
            onBoardDeletedByUser?(boardID)
        case .leave:
            try await enabledCloudSync().leaveShared(boardID)
        case .removeFromICloud:
            try await enabledCloudSync().removeFromICloud(boardID)
        }
    }

    private func enabledCloudSync() throws -> CloudSyncController {
        guard let sync = cloudSync(), sync.isEnabled else { throw CloudSyncControllerError.disabled }
        return sync
    }

    /// O banco do `cloud` do manifesto do mural, lido agora, e quantos convidados já aceitaram o convite (de `shareStates`). `nil`
    /// para o rascunho, o mural só deste Mac ou sem sincronização ligada.
    private func cloudRole(of route: BoardRoute) async -> (database: BoardCloudInfo.Database, participants: Int)? {
        guard case .saved(let id) = route, let sync = cloudSync(),
            let database = role(for: (try? await registry.library.open(route))?.manifest.cloud)
        else { return nil }
        return (database, sync.shareStates[id]?.participants.count { $0.isAccepted } ?? 0)
    }

    /// Exclui o mural: fecha a aba dele gravando o que faltava, aposenta a sessão (nenhuma gravação tardia
    /// recria o pacote) e manda o pacote para o Lixo. A janela continua aberta, mesmo sem abas.
    func deleteBoard(_ route: BoardRoute) async throws {
        guard let boardID = Self.boardID(of: route) else { throw BoardLibraryError.unavailableRoute(route) }
        // Fechar a aba não para a música, mas o mural apagado não tem mais de onde ela vir.
        musicPlayback.stop(boardID: boardID)
        if let tab = tab(for: boardID), let closing = removeTab(tab.id) {
            await closing.session.handleWindowWillClose()
        }
        await registry.close(boardID)
        try await registry.library.deleteBoard(route)
        removeBoardCaches(boardID)
        libraryRevision &+= 1
        await refreshDraftAvailability()
    }

    // MARK: Interno

    /// Tira a aba da lista e escolhe a vizinha da direita (ou da esquerda). Não grava nem fecha a janela.
    private func removeTab(_ id: UUID) -> BoardTab? {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = tabs.remove(at: index)
        loadStarted.remove(removed.id)
        if id == selectedID {
            selectedID = nil
            if let next = tabs.indices.contains(index) ? tabs[index] : tabs.last {
                activate(next)
            }
        }
        if tabs.isEmpty {
            isSidebarVisible = true
        }
        libraryRevision &+= 1
        return removed
    }

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
