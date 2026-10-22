import MuralKit
import Observation
import StretchText
import SwiftUI
import os

struct BoardImportDestination: Equatable, Sendable {
    let route: BoardRoute
    let boardID: BoardID
    /// Stable identity of the session/panel presentation.  Autosave and
    /// revision generations are persistence details, not panel identity.
    let presentationEpoch: UUID
    let folderID: UUID?
}

struct MuralExportTransfer: Equatable, Sendable {
    let operationID: UUID
    let route: BoardRoute
    let boardID: BoardID
    let generation: UInt64
    let packageURL: URL
}

struct DetailScrollMetrics: Equatable {
    var containerSize: CGSize = .zero
    var contentSize: CGSize = .zero
    var contentInsets: EdgeInsets = EdgeInsets()
    var visibleRect: CGRect = .zero

    init() {}

    init(_ geometry: ScrollGeometry) {
        containerSize = geometry.containerSize
        contentSize = geometry.contentSize
        contentInsets = geometry.contentInsets
        visibleRect = geometry.visibleRect
    }
}

/// Identidade da apresentação que está autorizada a restaurar/capturar uma
/// posição.  A navegação pode trocar de item sem recriar imediatamente a
/// árvore SwiftUI; por isso o item sozinho não identifica um callback válido.
struct ReadingPresentationToken: Hashable, Sendable {
    let boardID: BoardID
    let generation: UInt64
    let navigationGeneration: UInt64
    let itemID: UUID
}

typealias ReadingPresentationFinalizer = @MainActor () -> Void

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
    /// Changes only when this presentation is explicitly invalidated.  It is
    /// deliberately independent of the board's autosave generation.
    private(set) var presentationEpoch = UUID()

    private(set) var model: BoardModel?
    private(set) var domainSession: BoardSession?
    private(set) var workspace: BoardWorkspaceState = .default
    /// Geração do domínio: avança a cada autosave. Só serve para saber se o conteúdo
    /// mudou (ex.: entre preparar e entregar uma exportação), nunca para validar callbacks.
    private(set) var generation: UInt64 = 0
    /// Identidade da apresentação carregada: muda só quando a sessão é (re)carregada.
    /// Tokens de restauração e leitura usam esta geração; se usassem a do autosave, um
    /// salvamento no meio da restauração deixaria a tela sem clique para sempre.
    private(set) var presentationGeneration: UInt64 = 0
    /// Depois de fechada (janela fechada, rascunho promovido), a janela não grava mais.
    private(set) var isClosed = false
    private(set) var restorationPhase: CanvasRestorationPhase = .loading
    private(set) var error: String?
    private(set) var isDirty = false
    private(set) var isSaving = false
    private(set) var navigationGeneration: UInt64 = 0
    private(set) var readingPositions: [UUID: ReadingPosition] = [:]
    private(set) var captionDrafts: [UUID: String] = [:]
    private(set) var importDestination: BoardImportDestination?
    private(set) var exportTransfer: MuralExportTransfer?
    private(set) var exportDocument: MuralPackageDocument?
    private(set) var isPreparingExport = false
    private(set) var isFinishingExport = false
    var isExporterPresented = false
    var successMessage: String?
    var warningMessage: String?
    /// Escolha das frases curtas pelo modelo do aparelho; `nil` quando desligada.
    private(set) var keySentences: KeySentenceCoordinator?
    /// Cartões marcados com ⌘-clique para apagar de uma vez. Valem só no nível aberto
    /// (mural ou pasta); trocar de nível limpa a marcação.
    private(set) var selectedItemIDs: Set<UUID> = []
    /// ⌘ segurado por um instante: os cartões mostram o seletor mesmo sem nada marcado.
    var isCommandSelecting = false
    /// Nota ou post-it aberto no modo de edição.
    private(set) var editingItemID: UUID?
    private(set) var noteDrafts: [UUID: NoteDraft] = [:]

    var path: [Destination] = []
    var filter: BoardFilter?
    var isImporterPresented = false

    @ObservationIgnored private var restoration = CanvasRestorationStateMachine()
    @ObservationIgnored private var pendingBoard: Board?
    @ObservationIgnored private var pendingWorkspace: BoardWorkspaceState?
    @ObservationIgnored private var pendingBoardSequence: UInt64?
    @ObservationIgnored private var pendingWorkspaceSequence: UInt64?
    @ObservationIgnored private var mutationSequence: UInt64 = 0
    @ObservationIgnored private var pendingAutosaveDebounce: Task<Void, Never>?
    @ObservationIgnored private var sessionPipeline: Task<Void, Never>?
    @ObservationIgnored private var leaveFlushTask: Task<Void, Never>?
    @ObservationIgnored private var windowCloseTask: Task<Void, Never>?
    @ObservationIgnored private var windowCloseHandled = false
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @ObservationIgnored private let cleanupTransferOperation: @Sendable (URL) async throws -> Void
    @ObservationIgnored private var pendingSaveCopyResult: Result<URL, any Error>?
    @ObservationIgnored private var restoreTarget: CGPoint?
    @ObservationIgnored private var autosaveFailed = false
    @ObservationIgnored private var restoringReadingItems: [UUID: ReadingPresentationToken] = [:]
    @ObservationIgnored private var readingFinalizers: [ReadingPresentationToken: ReadingPresentationFinalizer] = [:]
    /// Esta janela é dona de uma referência no registry (`acquire`/`release`).
    @ObservationIgnored private var ownsRegistryReference = false
    /// Último tamanho do canvas com a restauração pronta; só um resize agenda captura.
    @ObservationIgnored private var lastCanvasContainerSize: CGSize = .zero
    @ObservationIgnored private var canvasCaptureDebounce: Task<Void, Never>?
    @ObservationIgnored private var restorationWatchdog: Task<Void, Never>?
    /// Tempo máximo tentando alcançar a posição salva antes de liberar o canvas.
    @ObservationIgnored var restorationTimeout: Duration = .seconds(2)
    @ObservationIgnored private var restorationSignpost: OSSignpostIntervalState?
    /// Janelas abertas que o término do app espera gravar.
    @ObservationIgnored private let openSessions: OpenBoardSessions
    @ObservationIgnored private let usesOnDeviceModel: Bool
    /// Cartões criados pelo botão nesta sessão: se ficarem vazios, são descartados.
    @ObservationIgnored private var newItemIDs: Set<UUID> = []

    init(
        route: BoardRoute,
        registry: BoardSessionRegistry,
        cleanupTransfer: (@Sendable (URL) async throws -> Void)? = nil,
        openSessions: OpenBoardSessions = .shared,
        usesOnDeviceModel: Bool = LaunchConfiguration.usesOnDeviceModel()
    ) {
        self.route = route
        self.registry = registry
        self.openSessions = openSessions
        self.usesOnDeviceModel = usesOnDeviceModel
        self.cleanupTransferOperation =
            cleanupTransfer ?? { url in
                try await registry.library.cleanupTransfer(url)
            }
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

    var currentFolderID: UUID? {
        for destination in path.reversed() {
            if case .collection(let id) = destination { return id }
        }
        return nil
    }

    /// No mural e dentro de pasta dá para criar conteúdo; na página de um item, não.
    var acceptsNewContent: Bool {
        guard restorationPhase == .ready else { return false }
        if case .item = path.last { return false }
        return true
    }

    /// Pastas só existem soltas no mural: criar uma vale apenas com nada aberto por cima.
    var acceptsNewFolder: Bool {
        acceptsNewContent && path.isEmpty
    }

    private var workspaceTitle: String {
        // Manifest is loaded with the domain session; keeping the title in the
        // workspace adapter avoids a second source of truth in the view.
        manifestName
    }

    private(set) var manifestName = "Mural"

    func load() async {
        guard model == nil, !isClosed, route != .library else { return }
        restorationPhase = .loading
        do {
            let session = try await registry.acquire(route)
            ownsRegistryReference = true
            let board = await session.board
            let loadedWorkspace = await session.workspace
            let loadedGeneration = await session.generation
            let manifest = await session.manifest
            let packageURL = await session.repository.packageURL(for: boardID)
            await refreshDraftAvailability()
            // A janela pode ter fechado durante as esperas acima: devolve a referência.
            guard !isClosed else {
                await releaseRegistryReference()
                return
            }

            domainSession = session
            workspace = loadedWorkspace
            readingPositions = loadedWorkspace.readingPositions
            generation = loadedGeneration
            manifestName = manifest.name
            let store = BoardStore(directory: packageURL)
            model = BoardModel(board: board, store: store, persistence: .deferred)
            path = Self.destinations(from: loadedWorkspace.path, board: board)
            filter = Self.filter(from: loadedWorkspace.filter, path: path, board: board)

            presentationGeneration &+= 1
            openSessions.register(self)
            restorationSignpost = MuralSignposts.restoration.beginInterval("Restaurar canvas")
            restoration.begin(CanvasRestorationToken(boardID: boardID, generation: presentationGeneration))
            restorationPhase = restoration.phase
            zoom.configure(workspace: loadedWorkspace.canvas)
            error = nil
            if usesOnDeviceModel {
                keySentences = makeKeySentenceCoordinator()
                scheduleKeySentences()
            }
        } catch let loadError {
            error = loadError.localizedDescription
            restorationPhase = .loading
        }
    }

    /// Nova tentativa depois de "Mural indisponível" (ex.: arquivo momentaneamente ilegível).
    func retryLoad() async {
        guard model == nil, !isClosed else { return }
        error = nil
        await load()
    }

    private func releaseRegistryReference() async {
        guard ownsRegistryReference else { return }
        ownsRegistryReference = false
        // Uma sessão suja continua registrada para a próxima janela recuperar.
        _ = await registry.release(boardID)
    }

    private var canvasToken: CanvasRestorationToken {
        CanvasRestorationToken(boardID: boardID, generation: presentationGeneration)
    }

    func refreshDraftAvailability() async {
        actions.resumeDraftAvailable =
            (try? await registry.library.lifecycleState())?.lifecycle == .draft
    }

    func beginApplyingZoom() {
        guard restoration.applyZoom(for: canvasToken) else { return }
        restorationPhase = restoration.phase
    }

    func beginApplyingPosition() {
        guard restoration.applyPosition(for: canvasToken) else { return }
        restorationPhase = restoration.phase
        startRestorationWatchdog()
    }

    func confirmReady() {
        guard restoration.confirmReady(for: canvasToken) else { return }
        didBecomeReady()
    }

    private func didBecomeReady() {
        restorationPhase = restoration.phase
        if let restorationSignpost {
            MuralSignposts.restoration.endInterval("Restaurar canvas", restorationSignpost)
            self.restorationSignpost = nil
        }
        restorationWatchdog?.cancel()
        restorationWatchdog = nil
        lastCanvasContainerSize = zoom.viewport
    }

    /// Se a posição salva não for alcançada a tempo (alvo inalcançável por arredondamento,
    /// clamp diferente do ScrollView, resize contínuo), o canvas é liberado onde estiver.
    /// Só começa depois da primeira geometria real: sem layout, nada está visível.
    private func startRestorationWatchdog() {
        restorationWatchdog?.cancel()
        let expected = presentationGeneration
        let timeout = restorationTimeout
        restorationWatchdog = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard let self, !Task.isCancelled, !self.isClosed,
                self.presentationGeneration == expected,
                self.restoration.forceReady(for: self.canvasToken)
            else { return }
            self.didBecomeReady()
        }
    }

    func restoreCanvas(boardID callbackBoardID: BoardID, generation callbackGeneration: UInt64, metrics: CanvasScrollMetrics) {
        guard self.boardID == callbackBoardID, presentationGeneration == callbackGeneration, !isClosed else { return }
        zoom.apply(metrics)
        guard restorationPhase != .ready else {
            noteReadyCanvasGeometry(metrics)
            return
        }
        guard let center = workspace.canvas.logicalCenter else {
            if restorationPhase == .awaitingLayout {
                beginApplyingZoom()
                beginApplyingPosition()
                restoreTarget = .zero
                scroll(to: .zero)
                return
            }
            if restorationPhase == .applyingPosition, let restoreTarget,
                abs(metrics.contentOffset.x - restoreTarget.x) <= 1,
                abs(metrics.contentOffset.y - restoreTarget.y) <= 1
            {
                confirmReady()
            }
            return
        }
        let target = CanvasWorkspaceMath.targetOffset(
            logicalCenter: CGPoint(x: center.x, y: center.y),
            zoom: zoom.zoom,
            viewport: metrics.containerSize,
            contentSize: metrics.contentSize,
            contentInsets: metrics.contentInsets
        )
        if restorationPhase == .awaitingLayout {
            beginApplyingZoom()
            beginApplyingPosition()
            restoreTarget = target
            scroll(to: target)
            return
        }
        if restorationPhase == .applyingPosition {
            if restoreTarget.map({ !Self.isApproximatelyEqual($0, target) }) ?? true {
                restoreTarget = target
                scroll(to: target)
            } else if abs(metrics.contentOffset.x - target.x) <= 1,
                abs(metrics.contentOffset.y - target.y) <= 1
            {
                confirmReady()
            }
        }
    }

    private func scroll(to point: CGPoint) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            zoom.requestScroll(to: point)
        }
    }

    private static func isApproximatelyEqual(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        abs(lhs.x - rhs.x) <= 1 && abs(lhs.y - rhs.y) <= 1
    }

    /// Com o canvas pronto, rolagens do usuário são capturadas em `.idle` e o zoom no
    /// assentamento; aqui só um resize (tamanho do viewport mudou) agenda uma captura,
    /// com debounce. Nada é gravado a cada quadro de rolagem.
    private func noteReadyCanvasGeometry(_ metrics: CanvasScrollMetrics) {
        guard metrics.containerSize != lastCanvasContainerSize else { return }
        lastCanvasContainerSize = metrics.containerSize
        canvasCaptureDebounce?.cancel()
        canvasCaptureDebounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard let self, !self.isClosed else { return }
            self.recordCanvas(self.zoom.confirmedWorkspace())
        }
    }

    func acceptsPersistence(for boardID: BoardID, generation: UInt64) -> Bool {
        restoration.acceptsPersistence && !isClosed && self.boardID == boardID
            && presentationGeneration == generation
    }

    func setNavigation(path: [Destination], filter: BoardFilter?) {
        guard restoration.acceptsPersistence, !isClosed, let model else { return }
        // Sair da página de um cartão em edição grava o rascunho (e descarta o novo vazio).
        if let editingItemID, !path.contains(.item(editingItemID)) {
            finishEditing()
        }
        let newPath = Self.workspaceDestinations(from: path, board: model.board)
        let newFilter = filter.flatMap { Self.workspaceFilter(from: $0, path: path, board: model.board) }
        let previousPath = self.path
        self.path = Self.destinations(from: newPath, board: model.board)
        if self.path != previousPath { selectedItemIDs = [] }
        self.filter = Self.filter(from: newFilter, path: self.path, board: model.board)
        let retainedItemIDs = Set(
            newPath.compactMap { destination -> UUID? in
                guard case .item(let itemID) = destination else { return nil }
                return itemID
            })
        let finalizers = readingFinalizers.filter { token, _ in
            token.navigationGeneration == navigationGeneration
                && !retainedItemIDs.contains(token.itemID)
        }
        for (token, finalizer) in finalizers {
            finalizer()
            readingFinalizers.removeValue(forKey: token)
        }
        navigationGeneration &+= 1
        restoringReadingItems = restoringReadingItems.filter {
            $0.value.navigationGeneration == navigationGeneration
        }
        updateWorkspace { workspace in
            workspace.path = newPath
            workspace.filter = newFilter
        }
    }

    func recordCanvas(_ canvas: CanvasWorkspaceState) {
        guard restoration.acceptsPersistence, !isClosed else { return }
        updateWorkspace { $0.canvas = canvas }
    }

    func recordCanvas(boardID callbackBoardID: BoardID, generation callbackGeneration: UInt64, state: CanvasWorkspaceState) {
        guard acceptsPersistence(for: callbackBoardID, generation: callbackGeneration) else { return }
        recordCanvas(state)
    }

    func captureBoardIfNeeded() {
        guard let model, !isClosed else { return }
        mutationSequence &+= 1
        pendingBoard = model.board
        pendingBoardSequence = mutationSequence
        scheduleAutosave()
        scheduleKeySentences()
    }

    // MARK: Frases curtas

    private func makeKeySentenceCoordinator() -> KeySentenceCoordinator {
        KeySentenceCoordinator(
            source: { [weak self] itemID in
                self?.model?.item(id: itemID).flatMap(NoteFolding.source(of:))
            },
            apply: { [weak self] itemID, record in
                guard let self, self.model?.setKeySentences(record, for: itemID) == true else { return }
                self.captureBoardIfNeeded()
            })
    }

    /// Põe na fila os cartões com texto dobrável sem escolhas válidas. Cada texto
    /// é tentado uma vez por sessão, então chamar a cada mudança não repete nada.
    func scheduleKeySentences() {
        guard let keySentences, let model else { return }
        for item in model.board.items where NoteFolding.needsChoices(item) {
            keySentences.enqueue(item.id)
        }
    }

    /// A nota aberta na tela passa à frente da fila, se ainda faltam as frases dela.
    func prioritizeKeySentences(for itemID: UUID) {
        guard let item = model?.item(id: itemID), NoteFolding.needsChoices(item) else { return }
        keySentences?.enqueue(itemID, first: true)
    }

    /// Janela fechando: interrompe o modelo, conclui a edição e grava o que falta.
    func prepareToClose() async {
        keySentences?.cancelAll()
        finishEditing()
        await flushAndPrepareToLeave()
    }

    // MARK: Importação e exportação

    /// Captures the destination before the system panel opens. Focus and
    /// navigation are allowed to change while the panel is visible, but they
    /// must not redirect the files to another folder or board.
    func beginFileImport(folderID: UUID? = nil) {
        guard !isClosed else { return }
        importDestination = BoardImportDestination(
            route: route,
            boardID: boardID,
            presentationEpoch: presentationEpoch,
            folderID: folderID)
        isImporterPresented = true
    }

    /// Invalidates callbacks belonging to a panel/session that is no longer
    /// current without coupling that decision to autosave revisions.
    func invalidatePresentation() {
        presentationEpoch = UUID()
    }

    func importFiles(from urls: [URL]) async {
        guard let destination = importDestination else { return }
        importDestination = nil
        isImporterPresented = false
        guard destination.route == route,
            destination.boardID == boardID,
            destination.presentationEpoch == presentationEpoch,
            let model
        else {
            error = "A importação foi descartada porque o mural mudou enquanto o painel estava aberto."
            return
        }

        guard destination.folderID.map({ model.item(id: $0)?.kind == .folder }) ?? true else {
            error = "A pasta selecionada não existe mais neste mural."
            return
        }

        // O escopo de segurança fica aberto durante toda a cópia, que roda fora do Main Actor.
        let prepared = await SecurityScopedAccess.withAccess(to: urls) {
            await model.prepareFiles(urls, parentID: destination.folderID)
        }
        guard !isClosed, boardID == destination.boardID, presentationEpoch == destination.presentationEpoch else {
            model.discard(prepared)
            error = "A importação foi descartada porque o mural mudou enquanto o painel estava aberto."
            return
        }
        model.commit(prepared, into: destination.folderID)
        captureBoardIfNeeded()
    }

    /// Colar ou soltar: o conteúdo já foi lido; a cópia e a conversão rodam fora do Main
    /// Actor e o cartão entra depois, se a janela ainda for a mesma.
    func importPasted(_ content: PasteboardImporter.Content, into folderID: UUID?, animation: Animation?) async {
        guard let model, !isClosed else { return }
        let epoch = presentationEpoch
        let prepared: BoardModel.PreparedImport
        switch content {
        case .files(let urls):
            prepared = await model.prepareFiles(urls, parentID: folderID)
        case .data(let data, let fileExtension, let kind, let title):
            prepared = await model.prepareData(
                data, fileExtension: fileExtension, kind: kind, title: title, parentID: folderID)
        case .imageNeedingConversion(let data):
            guard let png = await PasteboardImporter.pngData(from: data) else {
                model.lastError = "A imagem copiada não pôde ser lida."
                return
            }
            prepared = await model.prepareData(
                png, fileExtension: "png", kind: .image, title: "Imagem colada", parentID: folderID)
        case .text(let text):
            withAnimation(animation) {
                if model.importText(text, into: folderID) == nil {
                    model.lastError = "O conteúdo copiado não pôde virar um cartão."
                }
            }
            captureBoardIfNeeded()
            return
        case .nothing:
            model.lastError = "O conteúdo copiado não pôde virar um cartão."
            return
        }
        guard !isClosed, presentationEpoch == epoch else {
            model.discard(prepared)
            return
        }
        withAnimation(animation) {
            _ = model.commit(prepared, into: folderID)
        }
        captureBoardIfNeeded()
    }

    // MARK: Edição de notas e post-its

    /// Cria um card de texto ou post-it vazio na pasta aberta (ou no mural) e abre a
    /// página dele já editando. Se ficar vazio ao concluir, ele é descartado.
    @discardableResult
    func createCard(_ kind: ItemKind) -> UUID? {
        guard restoration.acceptsPersistence, let model, kind == .text || kind == .sticky else { return nil }
        let folderID = currentFolderID
        let item = kind == .text ? model.createNote(into: folderID) : model.createSticky(into: folderID)
        newItemIDs.insert(item.id)
        captureBoardIfNeeded()
        let folders = path.filter {
            if case .collection = $0 { return true }
            return false
        }
        setNavigation(path: folders + [.item(item.id)], filter: nil)
        beginEditing(item.id)
        return item.id
    }

    /// Cria uma pasta no mural e a abre, vazia, por cima dele. Dentro de uma pasta ou na
    /// página de um item nada é criado.
    @discardableResult
    func createFolder(named name: String) -> UUID? {
        guard restoration.acceptsPersistence, !isClosed, path.isEmpty, let model else { return nil }
        let folder = model.createFolder(named: name)
        captureBoardIfNeeded()
        setNavigation(path: [.collection(folder.id)], filter: nil)
        return folder.id
    }

    /// Texto colado, no tipo escolhido no popup.
    func importPastedText(_ paste: PendingPaste, as kind: ItemKind) {
        guard let model else { return }
        if model.importText(paste.text, as: kind, into: paste.folderID) == nil {
            model.lastError = "O texto colado não pôde virar um cartão."
        }
        captureBoardIfNeeded()
    }

    func beginEditing(_ itemID: UUID) {
        guard let item = model?.item(id: itemID), item.kind == .text || item.kind == .sticky else { return }
        if let editingItemID, editingItemID != itemID {
            finishEditing()
        }
        editingItemID = itemID
    }

    /// Rascunho em andamento ou, sem ele, o conteúdo gravado do cartão.
    func noteDraft(for itemID: UUID) -> NoteDraft {
        noteDrafts[itemID] ?? model?.item(id: itemID).map(NoteDraft.init(item:)) ?? NoteDraft()
    }

    func setNoteDraft(_ draft: NoteDraft, for itemID: UUID) {
        noteDrafts[itemID] = draft
    }

    /// Grava o rascunho e sai da edição. Cartão criado pelo botão que ficou vazio é apagado.
    func finishEditing() {
        guard let itemID = editingItemID else { return }
        editingItemID = nil
        commitNoteDraft(for: itemID)
        if newItemIDs.remove(itemID) != nil, model?.item(id: itemID)?.isBlank == true {
            delete(itemID)
        }
    }

    /// Publica todos os rascunhos no mural, sem sair da edição.
    func commitNoteDrafts() {
        for itemID in Array(noteDrafts.keys) {
            commitNoteDraft(for: itemID)
        }
    }

    private func commitNoteDraft(for itemID: UUID) {
        guard let model, let draft = noteDrafts.removeValue(forKey: itemID), let item = model.item(id: itemID) else { return }
        switch item.kind {
        case .text: model.updateNote(itemID, title: draft.title, text: draft.text)
        case .sticky: model.updateSticky(itemID, text: draft.text, color: draft.color)
        default: return
        }
        captureBoardIfNeeded()
    }

    func beginSaveCopy() {
        guard exportTask == nil, exportTransfer == nil, exportDocument == nil,
            !isExporterPresented, !isFinishingExport, model != nil, !isClosed
        else { return }
        isPreparingExport = true
        exportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.prepareSaveCopy()
            self.exportTask = nil
            self.isPreparingExport = false
        }
    }

    private func prepareSaveCopy() async {
        let capturedRoute = route
        let capturedBoardID = boardID
        guard await flushAndPrepareToLeaveSuccessfully(),
            !isDirty,
            route == capturedRoute,
            boardID == capturedBoardID
        else {
            error = "Não foi possível preparar o mural para exportação."
            return
        }
        let capturedGeneration = generation
        do {
            let packageURL = try await registry.library.exportPackage(route)
            guard boardID == capturedBoardID, generation == capturedGeneration else {
                try? await registry.library.cleanupTransfer(packageURL)
                error = "A exportação foi cancelada porque o mural mudou."
                return
            }
            exportTransfer = MuralExportTransfer(
                operationID: UUID(),
                route: route,
                boardID: capturedBoardID,
                generation: capturedGeneration,
                packageURL: packageURL)
            exportDocument = MuralPackageDocument(stagingURL: packageURL)
            isExporterPresented = true
        } catch let exportError {
            self.error = "Não foi possível preparar a cópia do mural: \(exportError.localizedDescription)"
        }
    }

    func finishSaveCopy(
        _ result: Result<URL, any Error>?,
        operationID callbackOperationID: UUID
    ) async {
        let transfer = exportTransfer
        guard let transfer else { return }
        guard callbackOperationID == transfer.operationID, !isFinishingExport else { return }
        if let result {
            pendingSaveCopyResult = result
        }
        isFinishingExport = true
        isExporterPresented = false
        defer { isFinishingExport = false }
        do {
            try await cleanupTransferOperation(transfer.packageURL)
        } catch let cleanupError {
            self.error = "Não foi possível limpar o staging da exportação: \(cleanupError.localizedDescription)"
            return
        }
        let completedResult = pendingSaveCopyResult
        pendingSaveCopyResult = nil
        exportTransfer = nil
        exportDocument = nil
        error = nil
        if case .some(.failure) = completedResult {
            error = "Não foi possível salvar a cópia do mural."
        } else if completedResult != nil {
            successMessage = "Cópia do mural salva."
        }
    }

    func retrySaveCopyCleanup() async {
        guard let operationID = exportTransfer?.operationID else { return }
        await finishSaveCopy(nil, operationID: operationID)
    }

    func requestDraftPromotion() {
        guard case .welcomeDraft = route else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.promoteDraft(named: self.title)
        }
    }

    @discardableResult
    func promoteDraft(named requestedName: String) async -> BoardRoute? {
        guard case .welcomeDraft = route else { return nil }
        let name = Self.normalizedName(requestedName)
        guard await flushAndPrepareToLeaveSuccessfully() else { return nil }
        do {
            let promoted = try await registry.promoteWelcomeDraft(name: name)
            // O registry já aposentou a sessão do rascunho; esta janela não grava mais,
            // senão um autosave atrasado recriaria o package do rascunho.
            ownsRegistryReference = false
            markClosed()
            actions.resumeDraftAvailable = false
            successMessage = "Rascunho promovido para um mural salvo."
            return promoted
        } catch let promotionError {
            self.error = "Não foi possível salvar o rascunho: \(promotionError.localizedDescription)"
            return nil
        }
    }

    /// Renomeia pela própria sessão de domínio, na mesma fila dos autosaves: não há
    /// sessão antiga que possa regravar o nome anterior.
    func rename(to requestedName: String) async {
        let name = Self.normalizedName(requestedName)
        guard !isClosed, let domainSession else { return }
        let previous = sessionPipeline
        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                try await domainSession.rename(to: name)
                _ = try await domainSession.flush()
                self.manifestName = name
                self.successMessage = "Mural renomeado."
            } catch let renameError {
                self.error = "Não foi possível renomear o mural: \(renameError.localizedDescription)"
            }
            self.isDirty = await domainSession.isDirty
        }
        sessionPipeline = task
        await task.value
    }

    private static func normalizedName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Mural sem título" : trimmed
    }

    // MARK: Posições de leitura e drafts

    func readingPosition(for itemID: UUID) -> ReadingPosition? {
        readingPositions[itemID]
    }

    func readingPresentationToken(for itemID: UUID) -> ReadingPresentationToken {
        ReadingPresentationToken(
            boardID: boardID,
            generation: presentationGeneration,
            navigationGeneration: navigationGeneration,
            itemID: itemID)
    }

    func acceptsReadingPresentation(_ token: ReadingPresentationToken) -> Bool {
        token.boardID == boardID && token.generation == presentationGeneration
            && token.navigationGeneration == navigationGeneration
    }

    func registerReadingFinalizer(
        for token: ReadingPresentationToken,
        _ finalizer: @escaping ReadingPresentationFinalizer
    ) {
        guard acceptsReadingPresentation(token) else { return }
        readingFinalizers[token] = finalizer
    }

    func unregisterReadingFinalizer(for token: ReadingPresentationToken) {
        readingFinalizers.removeValue(forKey: token)
    }

    @discardableResult
    func beginReadingRestore(token: ReadingPresentationToken) -> ReadingPosition? {
        guard acceptsReadingPresentation(token) else { return nil }
        restoringReadingItems[token.itemID] = token
        return readingPositions[token.itemID]
    }

    @discardableResult
    func finishReadingRestore(token: ReadingPresentationToken) -> Bool {
        guard acceptsReadingPresentation(token), restoringReadingItems[token.itemID] == token else {
            return false
        }
        restoringReadingItems.removeValue(forKey: token.itemID)
        return true
    }

    func recordReadingPosition(_ position: ReadingPosition, token: ReadingPresentationToken) {
        guard acceptsReadingPresentation(token), token.itemID == position.targetItemID,
            restoringReadingItems[token.itemID] != token
        else { return }
        recordReadingPosition(
            position,
            boardID: token.boardID,
            generation: token.generation,
            navigationGeneration: token.navigationGeneration)
    }

    /// Marca a barreira local da tela que está restaurando uma posição. O
    /// callback inicial do ScrollView/PDFView é ignorado até `finish...`.
    @discardableResult
    func beginReadingRestore(
        for itemID: UUID,
        boardID callbackBoardID: BoardID? = nil,
        generation callbackGeneration: UInt64? = nil,
        navigationGeneration callbackNavigationGeneration: UInt64? = nil
    ) -> ReadingPosition? {
        let token = ReadingPresentationToken(
            boardID: callbackBoardID ?? boardID,
            generation: callbackGeneration ?? presentationGeneration,
            navigationGeneration: callbackNavigationGeneration ?? navigationGeneration,
            itemID: itemID)
        return beginReadingRestore(token: token)
    }

    func finishReadingRestore(for itemID: UUID) {
        restoringReadingItems.removeValue(forKey: itemID)
    }

    func recordReadingPosition(
        _ position: ReadingPosition,
        boardID callbackBoardID: BoardID,
        generation callbackGeneration: UInt64,
        navigationGeneration callbackNavigationGeneration: UInt64? = nil
    ) {
        guard acceptsPersistence(for: callbackBoardID, generation: callbackGeneration),
            callbackNavigationGeneration.map({ $0 == navigationGeneration }) ?? true,
            restoringReadingItems[position.targetItemID] == nil
        else { return }
        updateWorkspace { workspace in
            workspace.readingPositions[position.targetItemID] = position
        }
        readingPositions[position.targetItemID] = workspace.readingPositions[position.targetItemID]
    }

    func setReadingPosition(
        _ position: ReadingPosition,
        boardID callbackBoardID: BoardID,
        generation callbackGeneration: UInt64,
        navigationGeneration callbackNavigationGeneration: UInt64? = nil
    ) {
        recordReadingPosition(
            position,
            boardID: callbackBoardID,
            generation: callbackGeneration,
            navigationGeneration: callbackNavigationGeneration)
    }

    func removeReadingPosition(
        for itemID: UUID,
        boardID callbackBoardID: BoardID? = nil,
        generation callbackGeneration: UInt64? = nil
    ) {
        guard callbackBoardID.map({ $0 == boardID }) ?? true,
            callbackGeneration.map({ $0 == presentationGeneration }) ?? true
        else { return }
        guard readingPositions[itemID] != nil else { return }
        updateWorkspace { $0.readingPositions.removeValue(forKey: itemID) }
        readingPositions.removeValue(forKey: itemID)
    }

    // MARK: Parágrafos abertos

    /// Parágrafos que estavam abertos na nota, se ainda valem para `source`.
    func openStretchIDs(for itemID: UUID, source: String) -> [StretchID] {
        guard let memory = workspace.openStretches[itemID], memory.matches(source) else { return [] }
        return memory.openIDs
    }

    /// Guarda os parágrafos abertos agora; nenhum aberto apaga a memória da nota.
    func recordOpenStretches(_ ids: Set<StretchID>, for itemID: UUID, source: String) {
        updateWorkspace { workspace in
            if ids.isEmpty {
                workspace.openStretches.removeValue(forKey: itemID)
            } else {
                workspace.openStretches[itemID] = OpenStretchMemory(source: source, openIDs: ids)
            }
        }
    }

    func captionDraft(for itemID: UUID) -> String {
        captionDrafts[itemID] ?? model?.item(id: itemID)?.text ?? ""
    }

    func setCaptionDraft(_ text: String, for itemID: UUID) {
        captionDrafts[itemID] = text
    }

    /// Publica drafts no BoardModel antes de capturar o snapshot. A operação é
    /// síncrona no MainActor; a gravação de disco continua pertencendo ao
    /// `BoardSession` assíncrono.
    func commitCaptionDrafts() {
        guard let model else { return }
        for (itemID, text) in captionDrafts {
            guard model.item(id: itemID) != nil,
                model.item(id: itemID)?.text != (text.isEmpty ? nil : text)
            else { continue }
            model.setCaption(text, for: itemID)
        }
    }

    func delete(_ itemID: UUID) {
        guard let model, !isClosed, model.item(id: itemID) != nil else { return }
        model.delete(itemID)
        canonicalizeWorkspaceAfterContentMutation()
        captionDrafts.removeValue(forKey: itemID)
        noteDrafts.removeValue(forKey: itemID)
        newItemIDs.remove(itemID)
        selectedItemIDs.remove(itemID)
        if editingItemID == itemID { editingItemID = nil }
        restoringReadingItems.removeValue(forKey: itemID)
        captureBoardIfNeeded()
    }

    // MARK: Seleção

    /// Cartões do nível aberto, os únicos que entram na seleção; a página de um item não tem.
    var selectableItemIDs: Set<UUID> {
        guard let model else { return [] }
        switch path.last {
        case nil: return Set(model.rootItems.map(\.id))
        case .collection(let folderID)?: return Set(model.children(of: folderID).map(\.id))
        case .item?: return []
        }
    }

    /// Marcação que ainda vale: um cartão apagado ou guardado numa pasta sai sozinho.
    var currentSelection: Set<UUID> {
        selectedItemIDs.intersection(selectableItemIDs)
    }

    /// Seletor aberto: ⌘ segurado ou algum cartão marcado. Aberto, o clique marca em vez de abrir.
    var isSelecting: Bool {
        isCommandSelecting || !currentSelection.isEmpty
    }

    func toggleSelection(_ itemID: UUID) {
        guard !isClosed, selectableItemIDs.contains(itemID) else { return }
        if selectedItemIDs.remove(itemID) == nil {
            selectedItemIDs.insert(itemID)
        }
    }

    func clearSelection() {
        selectedItemIDs = []
    }

    /// Apaga de uma vez os cartões marcados; uma pasta leva o conteúdo junto, como ao apagar um só.
    func deleteSelection() {
        let itemIDs = currentSelection
        selectedItemIDs = []
        for itemID in itemIDs {
            delete(itemID)
        }
    }

    func move(_ itemID: UUID, to position: BoardPoint) {
        guard !isClosed else { return }
        model?.move(itemID, to: position)
        captureBoardIfNeeded()
    }

    func moveIntoFolder(_ itemID: UUID, folderID: UUID) {
        guard !isClosed else { return }
        model?.moveIntoFolder(itemID, folderID: folderID)
        canonicalizeWorkspaceAfterContentMutation()
        captureBoardIfNeeded()
    }

    func moveToBoard(_ itemID: UUID) {
        guard !isClosed else { return }
        model?.moveToBoard(itemID)
        canonicalizeWorkspaceAfterContentMutation()
        captureBoardIfNeeded()
    }

    func flushAndPrepareToLeave() async {
        guard !isClosed else { return }
        if let leaveFlushTask {
            await leaveFlushTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performFlushAndPrepareToLeave()
        }
        leaveFlushTask = task
        await task.value
        leaveFlushTask = nil
    }

    func flushAndPrepareToLeaveSuccessfully() async -> Bool {
        await flushAndPrepareToLeave()
        return !isDirty
    }

    /// Flushes the session once after the real `NSWindow` close notification.
    /// A failed flush deliberately leaves the registry entry in place so a
    /// later scene can recover the dirty session.  Repeated notifications
    /// share the in-flight operation and never retire the registry twice.
    /// Depois disso a janela fica fechada: callbacks tardios não gravam mais nada.
    func handleWindowWillClose() async {
        guard route != .library else { return }
        if let windowCloseTask {
            await windowCloseTask.value
            return
        }
        guard !windowCloseHandled else { return }
        windowCloseHandled = true
        invalidatePresentation()

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.prepareToClose()
            self.markClosed()
            await self.releaseRegistryReference()
        }
        windowCloseTask = task
        await task.value
        windowCloseTask = nil
    }

    /// Encerra as gravações desta janela: nenhum autosave, captura ou watchdog depois.
    private func markClosed() {
        isClosed = true
        openSessions.unregister(self)
        pendingAutosaveDebounce?.cancel()
        pendingAutosaveDebounce = nil
        canvasCaptureDebounce?.cancel()
        canvasCaptureDebounce = nil
        restorationWatchdog?.cancel()
        restorationWatchdog = nil
    }

    /// Consolida drafts, zoom e posição e grava pela mesma fila dos autosaves. Toda
    /// chamada à sessão de domínio passa por `sessionPipeline`: um flush paralelo a um
    /// `update` faria a sessão recusar a mutação e mostrar um erro falso.
    private func performFlushAndPrepareToLeave() async {
        guard let domainSession else { return }
        commitCaptionDrafts()
        commitNoteDrafts()
        captureBoardIfNeeded()
        let canvas = zoom.prepareToLeave()
        recordCanvas(canvas)
        pendingAutosaveDebounce?.cancel()
        pendingAutosaveDebounce = nil
        enqueueAutosave()
        isSaving = true
        defer { isSaving = false }
        await sessionPipeline?.value
        guard !autosaveFailed else {
            isDirty = true
            return
        }
        isDirty = await domainSession.isDirty
    }

    func retryFlush() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if exportTransfer != nil, !isExporterPresented, !isFinishingExport {
                await retrySaveCopyCleanup()
            } else {
                await flushAndPrepareToLeave()
            }
        }
    }

    private func updateWorkspace(_ update: (inout BoardWorkspaceState) -> Void) {
        guard restoration.acceptsPersistence, !isClosed else { return }
        var changed = workspace
        update(&changed)
        guard changed != workspace else { return }
        mutationSequence &+= 1
        workspace = changed
        readingPositions = changed.readingPositions
        pendingWorkspace = changed
        pendingWorkspaceSequence = mutationSequence
        scheduleAutosave()
    }

    private func canonicalizeWorkspaceAfterContentMutation() {
        guard let model, !isClosed else { return }
        let canonical = workspace.canonicalized(for: model.board).state
        guard canonical != workspace else { return }
        workspace = canonical
        readingPositions = canonical.readingPositions
        path = Self.destinations(from: canonical.path, board: model.board)
        filter = Self.filter(from: canonical.filter, path: path, board: model.board)
        navigationGeneration &+= 1
        mutationSequence &+= 1
        pendingWorkspace = canonical
        pendingWorkspaceSequence = mutationSequence
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        guard !isClosed else { return }
        pendingAutosaveDebounce?.cancel()
        pendingAutosaveDebounce = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled, !self.isClosed else { return }
                enqueueAutosave()
            } catch is CancellationError {
                return
            } catch {
                self?.error = error.localizedDescription
                self?.isDirty = true
            }
        }
    }

    private func enqueueAutosave() {
        guard let domainSession, !isClosed else { return }
        autosaveFailed = false
        let board = pendingBoard
        let savedWorkspace = pendingWorkspace
        let boardSequence = pendingBoardSequence
        let workspaceSequence = pendingWorkspaceSequence
        pendingBoard = nil
        pendingWorkspace = nil
        pendingBoardSequence = nil
        pendingWorkspaceSequence = nil
        let previous = sessionPipeline
        sessionPipeline = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            let signpost = MuralSignposts.persistence.beginInterval("Autosave")
            defer { MuralSignposts.persistence.endInterval("Autosave", signpost) }
            do {
                var expectedGeneration = await domainSession.generation
                if let board {
                    try await domainSession.update(board: board, expectedGeneration: expectedGeneration)
                    expectedGeneration = await domainSession.generation
                }
                if let savedWorkspace {
                    try await domainSession.update(workspace: savedWorkspace, expectedGeneration: expectedGeneration)
                }
                if await domainSession.isDirty {
                    let persisted = try await domainSession.flush()
                    // Só apaga a mídia que a versão gravada já não usa; uma exclusão feita
                    // durante esta gravação espera a próxima.
                    model?.finalizeDeferredDeletions(persistedBoard: persisted.board)
                }
                generation = await domainSession.generation
                isDirty = await domainSession.isDirty
                error = nil
                autosaveFailed = false
            } catch {
                let hasNewerBoard = pendingBoardSequence.map { $0 > (boardSequence ?? 0) } ?? false
                if let board, !hasNewerBoard {
                    pendingBoard = board
                    pendingBoardSequence = boardSequence
                }
                let hasNewerWorkspace = pendingWorkspaceSequence.map { $0 > (workspaceSequence ?? 0) } ?? false
                if let savedWorkspace, !hasNewerWorkspace {
                    pendingWorkspace = savedWorkspace
                    pendingWorkspaceSequence = workspaceSequence
                }
                isDirty = true
                autosaveFailed = true
                self.error = "Não foi possível salvar o mural: \(error.localizedDescription)"
            }
        }
    }

    private static func destinations(from values: [WorkspaceDestination], board: Board) -> [Destination] {
        values.compactMap { value in
            switch value {
            case .collection(let id):
                guard let item = board.item(id: id), item.kind == .folder else { return nil }
                return .collection(id)
            case .item(let id):
                guard board.item(id: id) != nil else { return nil }
                return .item(id)
            }
        }
    }

    private static func workspaceDestinations(from values: [Destination], board: Board) -> [WorkspaceDestination] {
        values.compactMap { value in
            switch value {
            case .collection(let id):
                guard let item = board.item(id: id), item.kind == .folder else { return nil }
                return .collection(id)
            case .item(let id):
                guard board.item(id: id) != nil else { return nil }
                return .item(id)
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
    @State private var externalImportError: String?
    @State private var externalImportNotice: String?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase

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
                    ContentUnavailableView {
                        Label("Mural indisponível", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Tentar de novo") { Task { await session.retryLoad() } }
                        Button("Abrir biblioteca") { openWindow(value: BoardRoute.library) }
                    }
                } else {
                    ProgressView("Abrindo mural…")
                }
            } else {
                RootView(session: session)
                    .id(session.boardID)
                    .navigationTitle(session.title)
            }
        }
        .background {
            if route != .library {
                WindowLifecycleObserver {
                    Task { @MainActor in
                        await session.handleWindowWillClose()
                    }
                }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
        }
        .task(id: route) {
            guard route != .library else { return }
            await session.load()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, route != .library else { return }
            Task { await session.refreshDraftAvailability() }
        }
        .onOpenURL { source in
            Task { await importExternalPackage(from: source) }
        }
        .alert(
            "Não foi possível importar o mural",
            isPresented: Binding(
                get: { externalImportError != nil },
                set: { if !$0 { externalImportError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(externalImportError ?? "")
        }
        .alert(
            "Importação concluída",
            isPresented: Binding(
                get: { externalImportNotice != nil },
                set: { if !$0 { externalImportNotice = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(externalImportNotice ?? "")
        }
    }

    private func importExternalPackage(from source: URL) async {
        guard source.pathExtension.lowercased() == "mural" else { return }
        do {
            let result = try await MuralPackageImport.importAsCopy(
                from: source, using: registry.library)
            openWindow(value: result.route)
            externalImportNotice =
                "O mural foi importado como uma cópia interna. O arquivo original não será alterado."
                + Self.workspaceNotice(for: result.workspaceStatus)
        } catch {
            externalImportError = error.localizedDescription
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

private struct BoardLibraryView: View {
    let registry: BoardSessionRegistry
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.muralCommandCoordinator) private var commandCoordinator
    @State private var entries: [BoardLibraryEntry] = []
    /// Packages que não puderam ser lidos; os outros murais continuam listados.
    @State private var unreadable: [BoardLibraryIssue] = []
    @State private var name = ""
    @State private var isCreating = false
    @State private var isPackageImporterPresented = false
    @State private var error: String?
    @State private var successMessage: String?
    @State private var warningMessage: String?
    @State private var actions = FocusedBoardActions()

    var body: some View {
        NavigationStack {
            List {
                ForEach(entries, id: \.route) { entry in
                    Button {
                        openWindow(value: entry.route)
                    } label: {
                        Label(entry.manifest.name, systemImage: entry.route.isDraft ? "doc.badge.clock" : "rectangle.on.rectangle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(
                        entry.route.isDraft
                            ? "welcome-draft-entry"
                            : "saved-board-entry-\(entry.manifest.id.rawValue.uuidString)")
                }
                if !unreadable.isEmpty {
                    Section {
                        Label(
                            unreadable.count == 1
                                ? "1 mural não pôde ser lido" : "\(unreadable.count) murais não puderam ser lidos",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.secondary)
                        .help(unreadable.map { "\($0.packageName): \($0.reason)" }.joined(separator: "\n"))
                    }
                }
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
        .focusedSceneValue(actions)
        .task { await refresh() }
        .task(id: commandCoordinator?.pending) {
            consumePendingCommand()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refresh() }
        }
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
        .fileImporter(
            isPresented: $isPackageImporterPresented,
            allowedContentTypes: [.muralPackage],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let source = urls.first else { return }
            importPackage(from: source)
        }
        .onChange(of: actions.request) { _, request in
            guard let request else { return }
            actions.request = nil
            switch request {
            case .newBoard:
                name = ""
                isCreating = true
            case .openMural:
                isPackageImporterPresented = true
            case .resumeDraft:
                Task { @MainActor in
                    guard let state = try? await registry.library.lifecycleState(),
                        state.lifecycle == .draft,
                        let draft = entries.first(where: {
                            guard case .welcomeDraft(let id) = $0.route else { return false }
                            return id == state.stableWelcomeID
                        })
                    else {
                        actions.resumeDraftAvailable = false
                        return
                    }
                    actions.resumeDraftAvailable = true
                    openWindow(value: draft.route)
                }
            case .rename, .promoteDraft, .newFolder:
                break
            }
        }
        .onChange(of: commandCoordinator?.pending) { _, _ in
            consumePendingCommand()
        }
        .alert(
            "Não foi possível abrir a biblioteca",
            isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
        .alert(
            "Importação concluída",
            isPresented: Binding(get: { successMessage != nil }, set: { if !$0 { successMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(successMessage ?? "")
        }
        .alert(
            "Aviso de importação",
            isPresented: Binding(get: { warningMessage != nil }, set: { if !$0 { warningMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(warningMessage ?? "")
        }
    }

    private func refresh() async {
        do {
            let report = try await registry.library.listReport()
            entries = report.entries
            unreadable = report.unreadable
            actions.resumeDraftAvailable =
                (try? await registry.library.lifecycleState())?.lifecycle == .draft
        } catch let loadError {
            self.error = loadError.localizedDescription
            actions.resumeDraftAvailable = false
        }
    }

    private func consumePendingCommand() {
        guard let commandCoordinator,
            let request = commandCoordinator.pending,
            let intent = commandCoordinator.consume(token: request.token)
        else { return }
        switch intent {
        case .newBoard:
            name = ""
            isCreating = true
        case .openMural:
            isPackageImporterPresented = true
        }
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

    private func importPackage(from source: URL) {
        Task {
            do {
                let result = try await MuralPackageImport.importAsCopy(
                    from: source, using: registry.library)
                let importedName = try await registry.library.open(result.route)?.manifest.name ?? "Mural"
                await refresh()
                openWindow(value: result.route)
                successMessage =
                    "Mural ‘\(importedName)’ importado como uma cópia interna. "
                    + "O arquivo original não será alterado."
                switch result.workspaceStatus {
                case .loaded:
                    break
                case .missing:
                    warningMessage = "O estado visual do mural importado estava ausente; o conteúdo foi aberto com a visualização padrão."
                case .corrupted(let filename):
                    warningMessage =
                        "O estado visual do mural importado estava corrompido (\(filename)); "
                        + "o conteúdo foi aberto com a visualização padrão."
                case .futureSchema(let version):
                    warningMessage =
                        "O estado visual do mural importado usa uma versão futura (\(version)); "
                        + "o conteúdo foi aberto com a visualização padrão."
                }
            } catch let importError {
                self.error = importError.localizedDescription
            }
        }
    }
}

extension BoardRoute {
    fileprivate var isDraft: Bool {
        if case .welcomeDraft = self { return true }
        return false
    }
}
