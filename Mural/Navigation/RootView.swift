import AppKit
import MuralKit
import MusicKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Host de uma cena de mural. O estado de navegação vive na sessão da janela,
/// nunca em estado global ou num `@State` compartilhado entre cenas.
struct RootView: View {
    let session: BoardWindowSession

    var body: some View {
        if let model = session.model {
            LoadedRootView(session: session, model: model)
        } else if let error = session.error {
            ContentUnavailableView("Mural indisponível", systemImage: "exclamationmark.triangle", description: Text(error))
        } else {
            ProgressView("Abrindo mural…")
        }
    }
}

/// Empilha os três níveis (mural → pasta → item) num único ZStack, para que cada
/// nível cresça a partir do cartão clicado, e recebe ⌘V, arrastar e importar.
private struct LoadedRootView: View {
    @Bindable var session: BoardWindowSession
    let model: BoardModel

    @State private var isFolderInfoPresented = false
    @State private var isRenamePresented = false
    @State private var boardNameDraft = ""
    @State private var isNewFolderPresented = false
    @State private var isReminderPickerPresented = false
    @State private var isPhotoPickerPresented = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var freeTextEditor: BoardFreeTextEditorRequest?
    @State private var folderNameDraft = ""
    /// Cartão esperando o nome novo (Renomear… no menu dele).
    @State private var renamingCard: CardRenameRequest?
    @State private var cardNameDraft = ""
    /// Cartão esperando uma legenda nova (Adicionar/Editar legenda… no menu dele).
    @State private var captioningCard: CardCaptionRequest?
    @State private var cardCaptionDraft = ""
    @State private var isConfirmingSelectionDelete = false
    /// Espera curta antes de abrir o seletor ao segurar ⌘: some se o ⌘ era de um atalho.
    @State private var commandHoldTask: Task<Void, Never>?
    /// Texto solto colado, esperando a escolha do tipo no popup.
    @State private var pendingPaste: PendingPaste?
    @State private var linkPreviewCoordinator: LinkPreviewCoordinator?
    @State private var musicArtworkCoordinator: MusicArtworkCoordinator?
    @FocusState private var isCanvasFocused: Bool
    @Namespace private var heroNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// As abas da janela: novo mural, importação e rascunho promovido passam por elas.
    @Environment(MuralTabs.self) private var tabs: MuralTabs?
    @Environment(\.undoManager) private var undoManager

    private var path: [Destination] { session.path }
    private var filter: BoardFilter? { session.filter }

    private var hero: HeroContext {
        HeroContext(namespace: heroNamespace, isEnabled: !reduceMotion, presented: Set(path.map(\.id)))
    }

    /// Pasta aberta no topo da pilha: é onde o conteúdo colado entra.
    private var currentFolderID: UUID? {
        for destination in path.reversed() {
            if case .collection(let id) = destination { return id }
        }
        return nil
    }

    /// Pasta ou cartão aberto, como subtítulo da janela (ex.: "Viagem › Hotel").
    private var breadcrumb: String {
        path.compactMap { model.item(id: $0.id)?.title }.joined(separator: " › ")
    }

    private var navigationAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.45)
    }

    private var importAnimation: Animation? {
        reduceMotion ? nil : .smooth
    }

    private var errorTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }

    var body: some View {
        withReminderSync(withDialogs(withSelection(boardContent)))
            .musicSubscriptionOffer(
                isPresented: musicOfferBinding,
                options: MusicSubscriptionOffer.Options(
                    messageIdentifier: .playMusic,
                    itemID: session.musicPlayback.offer?.catalogID.map { MusicItemID($0) })
            )
            .background { SaveCopyExporter(session: session) }
    }

    /// O mural livre, com tudo o que os cartões chamam.
    private var canvas: some View {
        BoardCanvasView(
            model: model,
            hero: hero,
            filter: filter,
            colorFilter: session.colorFilter,
            zoom: session.zoom,
            onOpen: open,
            boardID: session.boardID,
            // Identidade da apresentação, não a geração do autosave.
            generation: session.presentationGeneration,
            // Chamado a cada quadro de rolagem: só conduz a restauração e nota resize.
            // A posição é gravada em `.idle`, no assentamento do zoom e após resize.
            onCanvasGeometryReady: { boardID, generation, metrics in
                session.restoreCanvas(boardID: boardID, generation: generation, metrics: metrics)
            },
            onCanvasChange: { boardID, generation, state in
                session.recordCanvas(boardID: boardID, generation: generation, state: state)
            },
            onDelete: session.delete,
            onMoveToBoard: session.moveToBoard,
            onMoveIntoFolder: session.moveIntoFolder,
            onSetColorTag: { session.setColorTag($1, for: $0) },
            onToggleReminder: toggleReminder,
            onToggleMusic: toggleMusic,
            musicPhase: session.musicPhase(of:),
            onMove: session.move,
            onFreeTextEdit: beginEditingFreeText,
            onFreeTextMove: session.moveFreeText,
            onFreeTextDelete: session.deleteFreeText,
            onRename: beginRenameCard,
            onEditCaption: beginEditingCaption,
            selection: canvasSelection
        )
    }

    /// O mural, os níveis abertos e o que age sobre eles. Folhas e avisos ficam em
    /// `withDialogs`: numa cadeia só, o compilador não checava os tipos a tempo.
    @ViewBuilder
    private var boardContent: some View {
        ZStack {
            // Níveis cobertos não recebem cliques nem aparecem para a leitura de tela.
            backgroundCanvas

            ForEach(path.indices, id: \.self) { index in
                let destination = path[index]
                destinationLayer(destination, index: index)
            }
        }
        .environment(\.linkPreviewFiles, LinkPreviewFiles(directory: LaunchConfiguration.linkPreviewsDirectory(for: session.boardID)))
        .environment(\.linkPreviewCoordinator, linkPreviewCoordinator)
        .environment(\.musicArtworkCoordinator, musicArtworkCoordinator)
        // Passa por baixo da barra da janela, mas não da barra lateral: um cartão atrás dela não
        // teria como ser clicado.
        .ignoresSafeArea(edges: .vertical)
        .navigationTitle(session.title)
        .navigationSubtitle(breadcrumb)
        .focusedSceneValue(session.restorationPhase == .ready ? session.actions : nil)
        .overlay(alignment: .topLeading) {
            FloatingToolbar(
                level: NavigationLevel(path: path), onBack: goBack,
                filter: Binding(get: { session.filter }, set: { session.setNavigation(path: session.path, filter: $0) }),
                colorFilter: $session.colorFilter
            )
            .padding(12)
            .containerCornerOffset(.top)
            .disabled(session.restorationPhase != .ready)
            .zIndex(100)
        }
        .overlay(alignment: .topTrailing) {
            folderInfoOverlay
        }
        .overlay(alignment: .bottom) {
            bottomBar
        }
        .overlay {
            restorationOverlay
        }
        .overlay(alignment: .top) {
            errorBanner
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isCanvasFocused)
        .onAppear { isCanvasFocused = true }
        // Depois de escolher o mural na barra lateral, o teclado volta para ele (⌘V, Esc).
        .onChange(of: tabs?.boardFocusRequest) { _, _ in
            // Já marcado como focado, o SwiftUI não tiraria o teclado da lista: desliga e liga de novo.
            isCanvasFocused = false
            Task { @MainActor in isCanvasFocused = true }
        }
        .onKeyPress(.escape) { handleEscape() }
        .onPasteCommand(of: PasteboardImporter.acceptedTypes + MusicPasteboardReader.pasteTypes) { _ in handlePaste() }
        .sheet(item: $pendingPaste) { paste in
            PasteChoiceSheet(paste: paste, onChoose: { kind in importPaste(paste, as: kind) }, onCancel: cancelPaste)
        }
        .dropDestination(for: URL.self) { urls, location in
            handleDrop(urls: urls, location: location)
        }
        .onDrop(
            of: MusicPasteboardReader.dropTypeIdentifiers,
            delegate: MusicDropDelegate { drafts, location in handleMusicDrop(drafts, location: location) }
        )
        .fileImporter(
            isPresented: $session.isImporterPresented,
            allowedContentTypes: PasteboardImporter.importableTypes,
            allowsMultipleSelection: true
        ) { result in
            importFilesResult(result)
        }
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $selectedPhotoItems,
            matching: .any(of: [.images, .videos]),
            preferredItemEncoding: .current
        )
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            selectedPhotoItems = []
            Task { await session.importPhotos(items) }
        }
        .onChange(of: session.actions.request) { _, request in
            guard let request else { return }
            session.actions.request = nil
            handle(request)
        }
        .onChange(of: model.board) { _, _ in
            session.captureBoardIfNeeded()
        }
        // O editor que tinha o foco sai de cena: o foco volta para o mural, onde ⌘V e Esc agem.
        .onChange(of: session.editingItemID) { _, editingItemID in
            restoreCanvasFocus(afterEditing: editingItemID)
        }
        .task {
            setupPreviewCoordinators()
        }
        .onDisappear {
            linkPreviewCoordinator?.cancelAll()
            musicArtworkCoordinator?.cancelAll()
        }
    }

    private var backgroundCanvas: some View {
        canvas
            .allowsHitTesting(path.isEmpty && session.restorationPhase == .ready)
            .accessibilityHidden(!path.isEmpty || session.restorationPhase != .ready)
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let message = model.lastError ?? session.error {
            ErrorBanner(message: message) { model.lastError = nil }
                .padding(12)
                .containerCornerOffset(.top)
                .transition(errorTransition)
        }
    }

    @ViewBuilder
    private var folderInfoOverlay: some View {
        if case .collection(let id)? = path.last, let folder = model.item(id: id) {
            FolderInfoButton(folder: folder, children: model.children(of: id), isPresented: $isFolderInfoPresented)
                .padding(12)
                .containerCornerOffset(.top)
        }
    }

    @ViewBuilder
    private var restorationOverlay: some View {
        if session.restorationPhase != .ready {
            ProgressView("Restaurando mural…")
                .padding(20)
                .glassEffect()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Restaurando mural")
        }
    }

    private func setupPreviewCoordinators() {
        let files = LinkPreviewFiles(directory: LaunchConfiguration.linkPreviewsDirectory(for: session.boardID))
        if linkPreviewCoordinator == nil {
            linkPreviewCoordinator = LinkPreviewCoordinator(
                model: model, files: files, fetcher: LaunchConfiguration.linkPreviewFetcher())
        }
        if musicArtworkCoordinator == nil {
            musicArtworkCoordinator = MusicArtworkCoordinator(
                model: model, files: files, fetcher: LaunchConfiguration.musicArtworkFetcher())
        }
    }

    private func restoreCanvasFocus(afterEditing itemID: UUID?) {
        if itemID == nil { isCanvasFocused = true }
    }

    private func handleDrop(urls: [URL], location: CGPoint) -> Bool {
        let files = urls.filter(\.isFileURL)
        let folder = currentFolderID
        let animation = importAnimation
        let anchor = session.dropAnchor(localPoint: location)
        if !files.isEmpty {
            Task { await session.importPasted(.files(files), into: folder, anchor: anchor, animation: animation) }
        }
        let music = urls.filter { !$0.isFileURL }.compactMap {
            AppleMusicLink.snapshot(from: $0, title: nil).map { MusicDraft(snapshot: $0) }
        }
        if !music.isEmpty { importMusic(music, into: folder, anchor: anchor, animation: animation) }
        return !files.isEmpty || !music.isEmpty
    }

    private func handleMusicDrop(_ drafts: [MusicDraft], location: CGPoint) -> Bool {
        guard !drafts.isEmpty else { return false }
        importMusic(
            drafts, into: currentFolderID, anchor: session.dropAnchor(localPoint: location), animation: importAnimation)
        return true
    }

    private func handlePaste() {
        if case .item(let noteID)? = path.last, session.editingItemID != noteID,
            session.model?.item(id: noteID)?.kind == .text,
            let pieces = NoteImagePaste.read(from: .general)
        {
            Task { await session.appendImages(pieces, toNote: noteID) }
            return
        }
        // Do Música (⌘C de faixa, link music.apple.com): cartão de música. Sem nada legível, segue o colar comum.
        let music = MusicPasteboardReader.drafts(from: .general)
        if !music.isEmpty {
            importMusic(music, into: currentFolderID, anchor: session.visibleBoardAnchor, animation: importAnimation)
            return
        }
        let content = PasteboardImporter.read()
        let folder = currentFolderID
        if case .text(let text) = content {
            pendingPaste = PendingPaste(text: text, folderID: folder, anchor: session.visibleBoardAnchor)
            return
        }
        let animation = importAnimation
        let anchor = session.visibleBoardAnchor
        Task { await session.importPasted(content, into: folder, anchor: anchor, animation: animation) }
    }

    private func importMusic(
        _ drafts: [MusicDraft], into folderID: UUID?, anchor: BoardPoint?, animation: Animation?
    ) {
        let ids = session.importMusic(
            drafts, into: folderID, at: anchor, artwork: musicArtworkCoordinator, animation: animation)
        musicArtworkCoordinator?.request(ids)
    }

    private func handleEscape() -> KeyPress.Result {
        if !session.currentSelection.isEmpty {
            session.clearSelection()
            return .handled
        }
        if session.editingItemID != nil {
            session.finishEditing()
            return .handled
        }
        if isFolderInfoPresented {
            isFolderInfoPresented = false
            return .handled
        }
        guard !path.isEmpty else { return .ignored }
        goBack()
        return .handled
    }

    private func importFilesResult(_ result: Result<[URL], any Error>) {
        guard case .success(let urls) = result else { return }
        Task { await session.importFiles(from: urls) }
    }

    @ViewBuilder
    private func destinationLayer(_ destination: Destination, index: Int) -> some View {
        let isTop = index == path.count - 1
        pageBackground(for: destination)
            .heroLink(destination.id, hero)
            .zIndex(Double(index * 2 + 1))
        destinationContent(destination)
            .allowsHitTesting(isTop)
            .accessibilityHidden(!isTop)
            .transition(.opacity)
            .zIndex(Double(index * 2 + 2))
    }

    // MARK: Música

    /// Oferta de assinatura só na janela do mural que pediu; ao fechar, zera o pedido.
    private var musicOfferBinding: Binding<Bool> {
        Binding(
            get: { session.musicPlayback.offer?.boardID == session.boardID },
            set: { if !$0 { session.musicPlayback.offer = nil } })
    }

    private func toggleMusic(_ id: UUID) {
        Task {
            await session.toggleMusic(id)
            await session.completeMusicArtwork(id, artwork: musicArtworkCoordinator)
        }
    }

    // MARK: Lembretes

    private func toggleReminder(_ id: UUID) {
        Task { await session.toggleReminder(id) }
    }

    /// Confere os cartões de lembrete com o app Lembretes ao ficar pronto, ao mudar e ao voltar ao app.
    private func withReminderSync(_ content: some View) -> some View {
        content
            .task(id: session.restorationPhase == .ready) {
                guard session.restorationPhase == .ready, !model.reminderItems.isEmpty else { return }
                await session.refreshReminders()
            }
            // Mudanças no app Lembretes chegam em rajada: espera um instante e confere uma vez só.
            .task(id: session.reminders.changeCount) {
                guard session.restorationPhase == .ready else { return }
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, !model.reminderItems.isEmpty else { return }
                await session.refreshReminders()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                guard session.restorationPhase == .ready, !model.reminderItems.isEmpty else { return }
                Task { await session.refreshReminders() }
            }
    }

    // MARK: Seletor de ⌘

    /// Segurar ⌘ abre o seletor; ⌫ apaga o que está marcado, com confirmação.
    private func withSelection(_ content: some View) -> some View {
        content
            .onModifierKeysChanged(mask: .command, initial: false) { _, keys in
                commandHoldTask?.cancel()
                guard keys.contains(.command) else {
                    session.isCommandSelecting = false
                    return
                }
                // Um atalho (⌘V, ⌘W…) solta o ⌘ antes disso: o seletor não pisca a cada atalho.
                commandHoldTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    session.isCommandSelecting = true
                }
            }
            // ⌘-Tab: o app perde o foco antes de o ⌘ ser solto, e a janela não vê a soltura.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                commandHoldTask?.cancel()
                session.isCommandSelecting = false
            }
            .onDeleteCommand(perform: selectionDeleteAction)
            .confirmationDialog(selectionDeleteTitle, isPresented: $isConfirmingSelectionDelete) {
                Button("Apagar", role: .destructive, action: deleteSelection)
            } message: {
                Text(selectionDeleteWarning)
            }
    }

    /// Seletor dos cartões soltos, só com o mural na frente.
    private var canvasSelection: CardSelection? {
        path.isEmpty ? CardSelection(session: session) : nil
    }

    /// Barra do centro inferior: a de criação ou, com o seletor aberto, a da seleção.
    @ViewBuilder
    private var bottomBar: some View {
        if session.acceptsNewContent {
            let newFreeTextAction: (() -> Void)? = path.isEmpty ? { beginNewFreeText() } : nil
            Group {
                if session.isSelecting {
                    SelectionBar(
                        count: session.currentSelection.count,
                        onColor: { color in
                            withAnimation(reduceMotion ? nil : .smooth) { session.colorSelection(color) }
                        },
                        onDelete: { isConfirmingSelectionDelete = true },
                        onCancel: { session.clearSelection() })
                } else {
                    CreationBar(
                        onNewNote: { createCard(.text) },
                        onNewSticky: { createCard(.sticky) },
                        onNewFreeText: newFreeTextAction,
                        onNewFolder: newFolderAction,
                        onAddFiles: { session.beginFileImport(folderID: currentFolderID) },
                        onAddPhotos: {
                            session.beginPhotoImport(folderID: currentFolderID)
                            isPhotoPickerPresented = true
                        },
                        onAddReminders: { isReminderPickerPresented = true })
                }
            }
            .padding(.bottom, 18)
            .transition(.opacity)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: session.isSelecting)
        }
    }

    /// ⌫ só age com algo marcado; sem nada, o comando Apagar fica desligado.
    private var selectionDeleteAction: (() -> Void)? {
        guard !session.currentSelection.isEmpty else { return nil }
        return { isConfirmingSelectionDelete = true }
    }

    private var selectionDeleteTitle: String {
        let count = session.currentSelection.count
        return count == 1 ? "Apagar 1 item?" : "Apagar \(count) itens?"
    }

    private var selectionDeleteWarning: String {
        let items = session.currentSelection.compactMap { model.item(id: $0) }
        return ItemKind.deleteWarning(forSelection: items) { model.descendantCount(of: $0) }
    }

    private func deleteSelection() {
        withAnimation(reduceMotion ? nil : .smooth) {
            session.deleteSelection()
        }
        isCanvasFocused = true
    }

    /// Folhas de nome (renomear o mural e nova pasta) e avisos da sessão.
    private func withDialogs(_ content: some View) -> some View {
        content
            .sheet(isPresented: $isRenamePresented) {
                nameSheet(title: "Renomear mural", text: $boardNameDraft, actionTitle: "Renomear") {
                    renameBoard(to: boardNameDraft)
                }
            }
            .sheet(isPresented: $isNewFolderPresented) {
                nameSheet(title: "Nova pasta", placeholder: "Nome da pasta", text: $folderNameDraft, actionTitle: "Criar") {
                    createFolder(named: folderNameDraft)
                }
            }
            .sheet(item: $renamingCard) { request in
                nameSheet(
                    title: "Renomear cartão", placeholder: "Nome do cartão", text: $cardNameDraft,
                    actionTitle: "Renomear"
                ) {
                    renameCard(request.id)
                }
            }
            .sheet(item: $captioningCard) { request in
                captionSheet(for: request.id)
            }
            .sheet(isPresented: $isReminderPickerPresented) {
                ReminderPickerSheet(session: session)
            }
            .sheet(item: $freeTextEditor) { request in
                if let freeText = model.freeText(id: request.id) {
                    BoardFreeTextEditorView(
                        initialText: freeText.text,
                        onSave: { text in
                            if request.isNew && BoardFreeText.normalized(text).isEmpty {
                                session.deleteFreeText(request.id)
                            } else {
                                session.updateFreeText(request.id, text: text)
                            }
                            freeTextEditor = nil
                            isCanvasFocused = true
                        },
                        onCancel: {
                            if request.isNew { session.deleteFreeText(request.id) }
                            freeTextEditor = nil
                            isCanvasFocused = true
                        }
                    )
                }
            }
            .alert(
                "Importação concluída",
                isPresented: Binding(
                    get: { session.successMessage != nil },
                    set: { if !$0 { session.successMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(session.successMessage ?? "")
            }
            .alert(
                "Aviso de importação",
                isPresented: Binding(
                    get: { session.warningMessage != nil },
                    set: { if !$0 { session.warningMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(session.warningMessage ?? "")
            }
    }

    @ViewBuilder
    private func nameSheet(
        title: String,
        placeholder: String = "Nome do mural",
        text: Binding<String>,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(action)
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) {
                    isRenamePresented = false
                    isNewFolderPresented = false
                    renamingCard = nil
                }
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    @ViewBuilder
    private func captionSheet(for itemID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.item(id: itemID)?.caption == nil ? "Adicionar legenda" : "Editar legenda")
                .font(.headline)
            TextField("Legenda", text: $cardCaptionDraft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .onSubmit { saveCaption(for: itemID) }
            Text("Deixe o campo vazio para remover a legenda.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) {
                    captioningCard = nil
                    isCanvasFocused = true
                }
                Button("Salvar") { saveCaption(for: itemID) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private func handle(_ request: FocusedBoardActionRequest) {
        switch request {
        case .rename:
            boardNameDraft = session.title
            isRenamePresented = true
        case .promoteDraft:
            // O rascunho vira mural salvo na mesma aba.
            Task {
                guard let route = await session.promoteDraft(named: session.title),
                    let tabs, let tabID = tabs.tabID(of: session)
                else { return }
                tabs.replace(tabID, with: route)
            }
        case .newFolder:
            beginNewFolder()
        case .tileBoard:
            tileBoard()
        case .addReminders:
            if session.acceptsNewContent { isReminderPickerPresented = true }
        }
    }

    private func renameBoard(to value: String) {
        isRenamePresented = false
        Task {
            await session.rename(to: value)
            tabs?.libraryDidChange()
        }
    }

    // MARK: Níveis

    @ViewBuilder
    private func pageBackground(for destination: Destination) -> some View {
        switch destination {
        case .collection(let id):
            // A pasta com cor tinge de leve a própria página; os itens de dentro continuam como estão.
            SurfaceFill(.collectionPage)
                .overlay {
                    if let tag = model.item(id: id)?.colorTag {
                        tag.color.opacity(0.06)
                    }
                }
        case .item: SurfaceFill(.itemPage)
        }
    }

    @ViewBuilder
    private func destinationContent(_ destination: Destination) -> some View {
        switch destination {
        case .collection(let id):
            if let folder = model.item(id: id) {
                CollectionView(
                    folder: folder, model: model, session: session, hero: hero, filter: filter,
                    colorFilter: session.colorFilter, onRename: beginRenameCard,
                    onEditCaption: beginEditingCaption
                ) {
                    childID in
                    // Pasta abre outro nível de pasta; o resto abre a página do item.
                    let isFolder = model.item(id: childID)?.kind == .folder
                    open([isFolder ? .collection(childID) : .item(childID)])
                }
            }
        case .item(let id):
            if let item = model.item(id: id) {
                ItemDetailView(item: item, model: model, session: session, onClose: goBack)
            }
        }
    }

    // MARK: Navegação

    /// Cada nível começa sem filtro: um destaque escolhido no mural não deve
    /// esmaecer o conteúdo da pasta. O foco fica no mural para ⌘V e Esc continuarem.
    private func open(_ destinations: [Destination]) {
        // Um nível já aberto não entra de novo: repetiria ids na pilha e na transição.
        let newLevels = destinations.filter { !path.contains($0) }
        guard !newLevels.isEmpty else { return }
        withAnimation(navigationAnimation) {
            session.setNavigation(path: session.path + newLevels, filter: nil)
        }
        isFolderInfoPresented = false
        isCanvasFocused = true
    }

    private func importPaste(_ paste: PendingPaste, as kind: ItemKind) {
        pendingPaste = nil
        withAnimation(importAnimation) {
            session.importPastedText(paste, as: kind)
        }
        isCanvasFocused = true
    }

    private func cancelPaste() {
        pendingPaste = nil
        isCanvasFocused = true
    }

    /// Organizar Mural: mosaico no formato da janela, com desfazer, e depois "Ajustar à janela".
    private func tileBoard() {
        let viewport = session.zoom.viewport
        let aspect = viewport.height > 0 ? viewport.width / viewport.height : BoardTiling.defaultAspect
        let animation: Animation? = reduceMotion ? nil : .smooth(duration: 0.5)
        var arrangement: BoardArrangement?
        withAnimation(animation) {
            arrangement = session.tileBoard(aspect: aspect)
        }
        guard let arrangement else { return }
        if let undoManager {
            session.registerUndo(of: arrangement, in: undoManager, animation: animation)
        }
        // O mural ainda não mediu a extensão nova: atualiza antes de ajustar o zoom.
        let extent = BoardLayout.extent(of: model.rootItems, freeTexts: model.freeTexts)
        session.zoom.contentExtent = CGSize(width: extent.width, height: extent.height)
        session.zoom.fitToWindow()
    }

    /// Botão Pasta da barra: só no mural, com nada aberto por cima.
    private var newFolderAction: (() -> Void)? {
        guard session.acceptsNewFolder else { return nil }
        return { beginNewFolder() }
    }

    /// Pede o nome da pasta nova; o pedido do menu chega aqui também.
    private func beginNewFolder() {
        guard session.acceptsNewFolder else { return }
        folderNameDraft = ""
        isNewFolderPresented = true
    }

    /// Cria a pasta no mural e a abre, vazia, crescendo a partir do cartão novo.
    private func createFolder(named name: String) {
        isNewFolderPresented = false
        withAnimation(navigationAnimation) {
            _ = session.createFolder(named: name)
        }
        isFolderInfoPresented = false
        isCanvasFocused = true
    }

    private func beginNewFreeText() {
        guard path.isEmpty, let id = session.createFreeText() else { return }
        freeTextEditor = BoardFreeTextEditorRequest(id: id, isNew: true)
    }

    private func beginEditingFreeText(_ id: UUID) {
        guard path.isEmpty, model.freeText(id: id) != nil else { return }
        freeTextEditor = BoardFreeTextEditorRequest(id: id, isNew: false)
    }

    /// Pede o nome novo de qualquer cartão, começando pelo atual.
    private func beginRenameCard(_ itemID: UUID) {
        cardNameDraft = model.item(id: itemID)?.title ?? ""
        renamingCard = CardRenameRequest(id: itemID)
    }

    private func renameCard(_ itemID: UUID) {
        renamingCard = nil
        session.renameItem(itemID, to: cardNameDraft)
        isCanvasFocused = true
    }

    private func beginEditingCaption(_ itemID: UUID) {
        cardCaptionDraft = model.item(id: itemID)?.caption ?? ""
        captioningCard = CardCaptionRequest(id: itemID)
    }

    private func saveCaption(for itemID: UUID) {
        session.setCaption(cardCaptionDraft, for: itemID)
        captioningCard = nil
        isCanvasFocused = true
    }

    /// Cria o cartão e abre a página dele já editando, crescendo a partir do cartão.
    private func createCard(_ kind: ItemKind) {
        withAnimation(navigationAnimation) {
            _ = session.createCard(kind)
        }
        isFolderInfoPresented = false
    }

    private func goBack() {
        guard !path.isEmpty else { return }
        withAnimation(navigationAnimation) {
            session.setNavigation(path: Array(session.path.dropLast()), filter: nil)
        }
        isFolderInfoPresented = false
        isCanvasFocused = true
    }
}

/// Isola o modificador de exportação da grande cadeia de overlays da janela,
/// evitando que o type-checker misture todos os destinos de navegação.
private struct SaveCopyExporter: View {
    @Bindable var session: BoardWindowSession

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .fileExporter(
                isPresented: $session.isExporterPresented,
                document: session.exportDocument,
                contentType: .muralPackage,
                defaultFilename: session.title
            ) { result in
                finish(result)
            } onCancellation: {
                finish(nil)
            }
    }

    private func finish(_ result: Result<URL, any Error>?) {
        guard let operationID = session.exportTransfer?.operationID else { return }
        Task { await session.finishSaveCopy(result, operationID: operationID) }
    }
}
