import MuralKit
import Observation
import SwiftUI

/// Adaptador MainActor de uma sessão de domínio para uma janela SwiftUI.
/// Cada instância pertence a exatamente um `BoardID`; não há estado de mural atual.
@MainActor
@Observable
final class BoardWindowSession {
    let boardID: BoardID
    let route: BoardRoute
    let registry: BoardSessionRegistry
    let zoom: CanvasZoomController
    let actions: FocusedBoardActions

    private(set) var model: BoardModel?
    private(set) var domainSession: BoardSession?
    private(set) var workspace: BoardWorkspaceState = .default
    private(set) var generation: UInt64 = 0
    private(set) var restorationPhase: CanvasRestorationPhase = .loading
    private(set) var error: String?
    private(set) var isDirty = false
    private(set) var isSaving = false

    var path: [Destination] = []
    var filter: BoardFilter?
    var isImporterPresented = false

    @ObservationIgnored private var restoration = CanvasRestorationStateMachine()
    @ObservationIgnored private var pendingCapture: Task<Void, Never>?
    @ObservationIgnored private var pendingWorkspaceSave: Task<Void, Never>?

    init(route: BoardRoute, registry: BoardSessionRegistry) {
        self.route = route
        self.registry = registry
        switch route {
        case .library:
            self.boardID = BoardID(rawValue: UUID())
        case .welcomeDraft(let id), .saved(let id):
            self.boardID = id
        }
        self.zoom = CanvasZoomController()
        self.actions = FocusedBoardActions()
        self.actions.session = self
        zoom.onWorkspaceChange = { [weak self] state in
            self?.recordCanvas(state)
        }
    }

    var title: String {
        domainSession.map { _ in workspaceTitle } ?? "Mural"
    }

    private var workspaceTitle: String {
        // Manifest is loaded with the domain session; keeping the title in the
        // workspace adapter avoids a second source of truth in the view.
        manifestName
    }

    private(set) var manifestName = "Mural"

    func load() async {
        guard model == nil else { return }
        restorationPhase = .loading
        do {
            let session = try await registry.open(route)
            let board = await session.board
            let loadedWorkspace = await session.workspace
            let loadedGeneration = await session.generation
            let manifest = await session.manifest
            let packageURL = await session.repository.packageURL(for: boardID)

            domainSession = session
            workspace = loadedWorkspace
            generation = loadedGeneration
            manifestName = manifest.name
            let store = BoardStore(directory: packageURL)
            model = BoardModel(board: board, store: store, persistence: .deferred)
            path = Self.destinations(from: loadedWorkspace.path, board: board)
            filter = Self.filter(from: loadedWorkspace.filter, path: path, board: board)

            let token = CanvasRestorationToken(boardID: boardID, generation: loadedGeneration)
            restoration.begin(token)
            restorationPhase = restoration.phase
            zoom.configure(workspace: loadedWorkspace.canvas)
            error = nil
        } catch let loadError {
            error = loadError.localizedDescription
            restorationPhase = .loading
        }
    }

    func beginApplyingZoom() {
        let token = CanvasRestorationToken(boardID: boardID, generation: generation)
        guard restoration.applyZoom(for: token) else { return }
        restorationPhase = restoration.phase
    }

    func beginApplyingPosition() {
        let token = CanvasRestorationToken(boardID: boardID, generation: generation)
        guard restoration.applyPosition(for: token) else { return }
        restorationPhase = restoration.phase
    }

    func confirmReady() {
        let token = CanvasRestorationToken(boardID: boardID, generation: generation)
        guard restoration.confirmReady(for: token) else { return }
        restorationPhase = restoration.phase
    }

    func restoreCanvas(viewport: CGSize, contentSize: CGSize) {
        zoom.viewport = viewport
        guard restorationPhase != .ready else { return }
        if restorationPhase == .awaitingLayout {
            beginApplyingZoom()
            beginApplyingPosition()
            let point: CGPoint
            if let center = workspace.canvas.logicalCenter {
                point = CanvasWorkspaceMath.targetOffset(
                    logicalCenter: CGPoint(x: center.x, y: center.y),
                    zoom: zoom.zoom,
                    viewport: viewport,
                    contentSize: contentSize
                )
            } else {
                point = .zero
            }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                zoom.scrollPosition.scrollTo(point: point)
            }
            return
        }
        if restorationPhase == .applyingPosition {
            confirmReady()
        }
    }

    func acceptsPersistence(for boardID: BoardID, generation: UInt64) -> Bool {
        restoration.acceptsPersistence && self.boardID == boardID && self.generation == generation
    }

    func setNavigation(path: [Destination], filter: BoardFilter?) {
        guard let model else { return }
        let newPath = Self.workspaceDestinations(from: path, board: model.board)
        let newFilter = filter.flatMap { Self.workspaceFilter(from: $0, path: path, board: model.board) }
        self.path = Self.destinations(from: newPath, board: model.board)
        self.filter = Self.filter(from: newFilter, path: self.path, board: model.board)
        updateWorkspace { workspace in
            workspace.path = newPath
            workspace.filter = newFilter
        }
    }

    func recordCanvas(_ canvas: CanvasWorkspaceState) {
        guard restoration.acceptsPersistence else { return }
        updateWorkspace { $0.canvas = canvas }
    }

    func recordCanvas(boardID callbackBoardID: BoardID, generation callbackGeneration: UInt64, state: CanvasWorkspaceState) {
        guard acceptsPersistence(for: callbackBoardID, generation: callbackGeneration) else { return }
        recordCanvas(state)
    }

    func captureBoardIfNeeded() {
        guard restoration.acceptsPersistence, let model, let domainSession else { return }
        let board = model.board
        let expectedGeneration = generation
        pendingCapture?.cancel()
        pendingCapture = Task { [weak self] in
            guard let self else { return }
            do {
                try await domainSession.update(board: board, expectedGeneration: expectedGeneration)
                generation = await domainSession.generation
                isDirty = await domainSession.isDirty
            } catch {
                self.error = error.localizedDescription
                self.isDirty = true
            }
        }
    }

    func flushAndPrepareToLeave() async {
        guard let domainSession else { return }
        let canvas = zoom.prepareToLeave()
        recordCanvas(canvas)
        isSaving = true
        defer { isSaving = false }
        do {
            await pendingCapture?.value
            await pendingWorkspaceSave?.value
            _ = try await domainSession.prepareToLeave()
            isDirty = await domainSession.isDirty
            error = nil
        } catch {
            isDirty = true
            self.error = "Não foi possível salvar o mural: \\(error.localizedDescription)"
        }
    }

    func retryFlush() {
        Task { await flushAndPrepareToLeave() }
    }

    private func updateWorkspace(_ update: (inout BoardWorkspaceState) -> Void) {
        guard restoration.acceptsPersistence else { return }
        var changed = workspace
        update(&changed)
        guard changed != workspace, let domainSession else { return }
        workspace = changed
        let expectedGeneration = generation
        pendingWorkspaceSave?.cancel()
        pendingWorkspaceSave = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled else { return }
                do {
                    try await domainSession.update(workspace: changed, expectedGeneration: expectedGeneration)
                } catch BoardSessionError.generationMismatch {
                    try await domainSession.update(workspace: changed, expectedGeneration: await domainSession.generation)
                }
                generation = await domainSession.generation
                isDirty = await domainSession.isDirty
            } catch is CancellationError {
                return
            } catch {
                self?.error = error.localizedDescription
                self?.isDirty = true
            }
        }
    }

    private static func destinations(from values: [WorkspaceDestination], board: Board) -> [Destination] {
        values.compactMap { value in
            switch value {
            case .collection(let id):
                guard let item = board.item(id: id.rawValue), item.kind == .folder else { return nil }
                return .collection(id.rawValue)
            case .item(let id):
                guard board.item(id: id.rawValue) != nil else { return nil }
                return .item(id.rawValue)
            }
        }
    }

    private static func workspaceDestinations(from values: [Destination], board: Board) -> [WorkspaceDestination] {
        values.compactMap { value in
            switch value {
            case .collection(let id):
                guard let item = board.item(id: id), item.kind == .folder else { return nil }
                return .collection(BoardID(id))
            case .item(let id):
                guard board.item(id: id) != nil else { return nil }
                return .item(BoardID(id))
            }
        }
    }

    private static func filter(from value: WorkspaceFilter?, path: [Destination], board: Board) -> BoardFilter? {
        guard let value, let filter = BoardFilter(rawValue: value.rawValue),
            BoardFilter.available(at: NavigationLevel(path: path)).contains(filter)
        else { return nil }
        return filter
    }

    private static func workspaceFilter(from value: BoardFilter, path: [Destination], board: Board) -> WorkspaceFilter? {
        guard BoardFilter.available(at: NavigationLevel(path: path)).contains(value) else { return nil }
        return WorkspaceFilter(rawValue: value.rawValue)
    }
}

/// Uma cena de biblioteca é deliberadamente separada das cenas de mural.
struct BoardWindowHost: View {
    let route: BoardRoute
    let registry: BoardSessionRegistry

    @State private var session: BoardWindowSession

    init(route: BoardRoute, registry: BoardSessionRegistry) {
        self.route = route
        self.registry = registry
        _session = State(initialValue: BoardWindowSession(route: route, registry: registry))
    }

    var body: some View {
        Group {
            if route == .library {
                BoardLibraryView(registry: registry)
            } else if session.model == nil {
                if let error = session.error {
                    ContentUnavailableView("Mural indisponível", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    ProgressView("Abrindo mural…")
                }
            } else {
                RootView(session: session)
                    .id(session.boardID)
                    .navigationTitle(session.title)
            }
        }
        .task(id: route) {
            guard route != .library else { return }
            await session.load()
        }
        .onDisappear {
            Task { await session.flushAndPrepareToLeave() }
        }
    }
}

private struct BoardLibraryView: View {
    let registry: BoardSessionRegistry
    @Environment(\.openWindow) private var openWindow
    @State private var entries: [BoardLibraryEntry] = []
    @State private var name = ""
    @State private var isCreating = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List(entries, id: \.route) { entry in
                Button {
                    openWindow(value: entry.route)
                } label: {
                    Label(entry.manifest.name, systemImage: entry.route.isDraft ? "doc.badge.clock" : "rectangle.on.rectangle")
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Murais")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Novo mural", systemImage: "plus") { isCreating = true }
                }
            }
            .overlay {
                if entries.isEmpty && error == nil {
                    ContentUnavailableView("Nenhum mural salvo", systemImage: "rectangle.on.rectangle")
                }
            }
            .alert(
                "Não foi possível abrir a biblioteca",
                isPresented: Binding(
                    get: { error != nil }, set: { if !$0 { error = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
        .task { await refresh() }
        .sheet(isPresented: $isCreating) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Novo mural").font(.headline)
                TextField("Nome do mural", text: $name)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancelar", role: .cancel) { isCreating = false }
                    Button("Criar", action: createBoard)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .frame(width: 360)
        }
    }

    private func refresh() async {
        do { entries = try await registry.library.list() } catch let loadError { self.error = loadError.localizedDescription }
    }

    private func createBoard() {
        let boardName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await createBoard(named: boardName.isEmpty ? "Mural sem título" : boardName) }
    }

    private func createBoard(named boardName: String) async {
        do {
            let route = try await registry.library.createNamedBoard(boardName)
            await refresh()
            isCreating = false
            openWindow(value: route)
        } catch let createError {
            error = createError.localizedDescription
        }
    }
}

extension BoardRoute {
    fileprivate var isDraft: Bool {
        if case .welcomeDraft = self { return true }
        return false
    }
}
