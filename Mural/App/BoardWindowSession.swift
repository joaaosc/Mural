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
    /// Destaque por cor; não é gravado e some ao trocar de nível, como cada nível começa sem filtro.
    var colorFilter: TagColor?
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

    /// Pasta nova vale no mural e dentro de pastas, até o último nível permitido pelo domínio.
    var acceptsNewFolder: Bool {
        acceptsNewContent && (model?.canCreateFolder(in: currentFolderID) ?? false)
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

    // MARK: Aba na frente ou no fundo

    /// A aba saiu da frente: grava onde o mural estava e deixa de aceitar posição até voltar. O modelo, os
    /// rascunhos de nota e a edição em andamento continuam na sessão e voltam com a aba.
    func suspendPresentation() {
        guard model != nil, !isClosed, restorationPhase != .loading else { return }
        isCommandSelecting = false
        selectedItemIDs = []
        if restoration.acceptsPersistence {
            recordCanvas(zoom.prepareToLeave())
        }
        // Respostas atrasadas de painéis abertos para a apresentação que saiu não valem mais.
        invalidatePresentation()
        restorationWatchdog?.cancel()
        restorationWatchdog = nil
        canvasCaptureDebounce?.cancel()
        canvasCaptureDebounce = nil
        if let restorationSignpost {
            MuralSignposts.restoration.endInterval("Restaurar canvas", restorationSignpost)
            self.restorationSignpost = nil
        }
        restoration = CanvasRestorationStateMachine()
        restorationPhase = restoration.phase
    }

    /// A aba voltou para a frente: o canvas novo restaura a posição gravada, como ao abrir o mural.
    func resumePresentation() {
        guard model != nil, !isClosed, restorationPhase == .loading else { return }
        presentationGeneration &+= 1
        restorationSignpost = MuralSignposts.restoration.beginInterval("Restaurar canvas")
        restoration.begin(canvasToken)
        restorationPhase = restoration.phase
        zoom.configure(workspace: workspace.canvas)
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
        if self.path != previousPath {
            selectedItemIDs = []
            colorFilter = nil
        }
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
        case .links(let drafts):
            withAnimation(animation) {
                if model.importLinks(drafts, into: folderID).isEmpty {
                    model.lastError = "O conteúdo copiado não pôde virar um cartão."
                }
            }
            captureBoardIfNeeded()
            return
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

    // MARK: Imagens coladas em notas

    /// Grava uma imagem colada em `Items/`. Os testes trocam para decidir quando a gravação termina.
    @ObservationIgnored var storeNoteImage: (NoteImagePaste.Source, BoardModel) async -> NoteAttachment? = {
        source, model in
        await NoteImagePaste.store(source, with: model)
    }

    /// Grava as imagens coladas e as liga à nota. Se a janela fechou ou a apresentação mudou no
    /// meio, descarta tudo e devolve `nil` para cada imagem.
    func prepareNoteImages(_ sources: [NoteImagePaste.Source], for itemID: UUID) async -> [NoteAttachment?] {
        guard let model, !isClosed else { return sources.map { _ in nil } }
        let epoch = presentationEpoch
        var stored: [NoteAttachment?] = []
        for source in sources {
            stored.append(await storeNoteImage(source, model))
        }
        guard !isClosed, presentationEpoch == epoch else {
            for attachment in stored.compactMap({ $0 }) { model.discardNoteImage(attachment) }
            return sources.map { _ in nil }
        }
        var result: [NoteAttachment?] = []
        for attachment in stored {
            if let attachment, model.addNoteAttachment(attachment, to: itemID) {
                result.append(attachment)
            } else {
                if let attachment { model.discardNoteImage(attachment) }
                result.append(nil)
            }
        }
        captureBoardIfNeeded()
        if result.contains(where: { $0 == nil }) {
            model.lastError = "A imagem colada não pôde ser lida."
        }
        return result
    }

    /// Troca o marcador provisório pelo Markdown final, no rascunho da nota ou, sem rascunho,
    /// no texto gravado. Serve quando o editor fechou antes de a imagem ficar pronta.
    func replacePendingImage(_ token: UUID, with markdown: String, in itemID: UUID) {
        if var draft = noteDrafts[itemID] {
            if let text = NoteImageMarkup.replacingPending(token, with: markdown, in: draft.text) {
                draft.text = text
                noteDrafts[itemID] = draft
            }
            return
        }
        guard let model, let item = model.item(id: itemID), item.kind == .text,
            let text = NoteImageMarkup.replacingPending(token, with: markdown, in: item.text ?? "")
        else { return }
        model.updateNote(itemID, title: item.title, text: text)
        captureBoardIfNeeded()
    }

    /// ⌘V com a página da nota aberta e sem editar: grava as imagens e acrescenta tudo ao fim do corpo.
    func appendImages(_ pieces: [NoteImagePaste.Piece], toNote itemID: UUID) async {
        guard let model, !isClosed, model.item(id: itemID)?.kind == .text else { return }
        var sources: [NoteImagePaste.Source] = []
        for case .image(let source) in pieces { sources.append(source) }
        let attachments = await prepareNoteImages(sources, for: itemID)
        guard !isClosed, let item = model.item(id: itemID), item.kind == .text else { return }
        var blocks: [String] = []
        var next = attachments.makeIterator()
        for piece in pieces {
            switch piece {
            case .text(let text):
                let trimmed = text.trimmingCharacters(in: .newlines)
                if !trimmed.isEmpty { blocks.append(trimmed) }
            case .image:
                if let attachment = next.next() ?? nil {
                    blocks.append(NoteImageMarkup.line(fileName: attachment.fileName))
                }
            }
        }
        guard !blocks.isEmpty else { return }
        let body = item.text ?? ""
        let addition = NoteImageMarkup.insertion(
            of: [blocks.joined(separator: "\n\n")], after: body[...], before: "")
        model.updateNote(itemID, title: item.title, text: body + addition)
        captureBoardIfNeeded()
    }

    // MARK: Lembretes

    /// Ponte com o app Lembretes; os testes trocam por uma versão falsa.
    @ObservationIgnored var reminders: any RemindersProviding = RemindersCenter.shared

    /// Cria um cartão para cada lembrete, na pasta aberta ou no mural.
    @discardableResult
    func addReminders(_ snapshots: [ReminderSnapshot]) -> [UUID] {
        guard restoration.acceptsPersistence, !isClosed, let model, !snapshots.isEmpty else { return [] }
        let created = model.addReminders(snapshots, into: currentFolderID)
        captureBoardIfNeeded()
        return created.map(\.id)
    }

    /// Confere cada cartão de lembrete com o app Lembretes e atualiza o que mudou ou sumiu.
    func refreshReminders() async {
        guard let model, !isClosed else { return }
        let epoch = presentationEpoch
        var results: [(UUID, ReminderLookup)] = []
        for item in model.reminderItems {
            guard let snapshot = item.reminder else { continue }
            results.append((item.id, await reminders.lookup(snapshot)))
        }
        guard !isClosed, presentationEpoch == epoch else { return }
        var changed = false
        for (id, lookup) in results {
            switch lookup {
            case .found(let snapshot):
                if model.updateReminder(id, with: snapshot) { changed = true }
            case .missing:
                if model.item(id: id)?.reminder?.isMissing == false {
                    model.markReminderMissing(id)
                    changed = true
                }
            case .unavailable:
                break
            }
        }
        if changed { captureBoardIfNeeded() }
    }

    /// Marca ou desmarca o lembrete como concluído no app Lembretes e no cartão.
    func toggleReminder(_ itemID: UUID) async {
        guard let model, !isClosed, let snapshot = model.item(id: itemID)?.reminder else { return }
        let epoch = presentationEpoch
        do {
            let updated = try await reminders.setCompleted(!snapshot.isCompleted, for: snapshot)
            guard !isClosed, presentationEpoch == epoch else { return }
            model.updateReminder(itemID, with: updated)
        } catch {
            guard !isClosed, presentationEpoch == epoch else { return }
            model.lastError = "Não foi possível marcar o lembrete no app Lembretes."
        }
        captureBoardIfNeeded()
    }

    /// Abre o lembrete no app Lembretes.
    func openReminder(_ itemID: UUID) {
        guard let snapshot = model?.item(id: itemID)?.reminder else { return }
        reminders.open(snapshot)
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

    /// Cria uma pasta na pasta aberta (ou solta no mural) e a abre, vazia, por cima do caminho
    /// atual. Na página de um item ou no último nível de pastas nada é criado.
    @discardableResult
    func createFolder(named name: String) -> UUID? {
        guard restoration.acceptsPersistence, !isClosed, acceptsNewFolder, let model else { return nil }
        let folder: BoardItem
        if let parentID = currentFolderID {
            guard let created = model.createFolder(named: name, into: parentID) else { return nil }
            folder = created
        } else {
            folder = model.createFolder(named: name)
        }
        captureBoardIfNeeded()
        setNavigation(path: path + [.collection(folder.id)], filter: nil)
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

    // MARK: Organizar

    /// Organizar Mural vale no mural, com nada aberto por cima e ao menos dois cartões soltos.
    var canTileBoard: Bool {
        acceptsNewContent && path.isEmpty && (model?.rootItems.count ?? 0) >= 2
    }

    /// Arruma os cartões soltos em mosaico BSP no formato `aspect` (largura ÷ altura da janela).
    /// - Returns: o caminho de volta para desfazer; `nil` se nenhum cartão mudou de lugar.
    @discardableResult
    func tileBoard(aspect: Double) -> BoardArrangement? {
        guard restoration.acceptsPersistence, !isClosed, path.isEmpty, let model else { return nil }
        let positions = BoardTiling.bsp(model.rootItems, aspect: aspect)
        let previous = model.arrange(positions)
        guard !previous.isEmpty else { return nil }
        captureBoardIfNeeded()
        return BoardArrangement(previous: previous, arranged: positions.filter { previous[$0.key] != nil })
    }

    /// Devolve a `previous` só os cartões que continuam onde a organização os pôs: um cartão movido
    /// depois fica onde a pessoa o deixou.
    /// - Returns: o caminho inverso (refazer); `nil` se nenhum cartão pôde voltar.
    @discardableResult
    func revert(_ arrangement: BoardArrangement) -> BoardArrangement? {
        guard restoration.acceptsPersistence, !isClosed, let model else { return nil }
        let restorable = arrangement.previous.filter { itemID, _ in
            guard let item = model.item(id: itemID), item.parentID == nil else { return false }
            return item.position == arrangement.arranged[itemID]
        }
        guard !restorable.isEmpty else { return nil }
        model.arrange(restorable)
        captureBoardIfNeeded()
        return BoardArrangement(
            previous: restorable, arranged: arrangement.arranged.filter { restorable[$0.key] != nil }
        ).reversed
    }

    /// Põe a organização na pilha de desfazer da janela; desfazer registra o refazer, e assim por diante.
    func registerUndo(of arrangement: BoardArrangement, in undoManager: UndoManager, animation: Animation?) {
        undoManager.registerUndo(withTarget: self) { [weak undoManager] session in
            var reverse: BoardArrangement?
            withAnimation(animation) { reverse = session.revert(arrangement) }
            guard let reverse, let undoManager else { return }
            session.registerUndo(of: reverse, in: undoManager, animation: animation)
        }
        undoManager.setActionName("Organizar Mural")
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

    /// Marca exatamente estes cartões (o retângulo de Shift + arrastar); os que não são do nível aberto ficam de fora.
    func select(_ itemIDs: Set<UUID>) {
        guard !isClosed else { return }
        let selection = itemIDs.intersection(selectableItemIDs)
        if selection != selectedItemIDs { selectedItemIDs = selection }
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

    /// Sobe o cartão para a pasta que contém a pasta dele (ou para o mural, se não houver).
    func moveUp(_ itemID: UUID) {
        guard !isClosed else { return }
        model?.moveUp(itemID)
        canonicalizeWorkspaceAfterContentMutation()
        captureBoardIfNeeded()
    }

    /// Define a cor do cartão (`nil` tira a cor) e agenda a gravação; escolher a cor que o cartão já tem não faz nada.
    func setColorTag(_ color: TagColor?, for itemID: UUID) {
        guard !isClosed else { return }
        guard model?.setColorTag(color, for: itemID) == true else { return }
        captureBoardIfNeeded()
    }

    /// Renomeia a pasta e agenda a gravação; nome vazio ou igual ao atual não muda nada.
    func renameFolder(_ itemID: UUID, to name: String) {
        guard !isClosed, model?.renameFolder(itemID, to: name) == true else { return }
        captureBoardIfNeeded()
    }

    /// Dá a cor (ou tira, com `nil`) a todos os cartões marcados, com uma gravação só. A marcação continua,
    /// para a pessoa poder fazer mais alguma coisa com os mesmos cartões.
    func colorSelection(_ color: TagColor?) {
        guard !isClosed, let model else { return }
        var changed = false
        for itemID in currentSelection where model.setColorTag(color, for: itemID) {
            changed = true
        }
        if changed { captureBoardIfNeeded() }
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
