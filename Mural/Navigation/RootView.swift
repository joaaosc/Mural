import AppKit
import MuralKit
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
    @State private var isPackageImporterPresented = false
    @State private var isNewBoardPresented = false
    @State private var isRenamePresented = false
    @State private var boardNameDraft = ""
    @State private var isNewFolderPresented = false
    @State private var folderNameDraft = ""
    @State private var isConfirmingSelectionDelete = false
    /// Espera curta antes de abrir o seletor ao segurar ⌘: some se o ⌘ era de um atalho.
    @State private var commandHoldTask: Task<Void, Never>?
    @State private var importError: String?
    /// Texto solto colado, esperando a escolha do tipo no popup.
    @State private var pendingPaste: PendingPaste?
    @FocusState private var isCanvasFocused: Bool
    @Namespace private var heroNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
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
        withDialogs(withSelection(boardContent))
    }

    /// O mural, os níveis abertos e o que age sobre eles. Folhas e avisos ficam em
    /// `withDialogs`: numa cadeia só, o compilador não checava os tipos a tempo.
    @ViewBuilder
    private var boardContent: some View {
        /// Captured while the exporter presentation is rendered. A later
        /// export cannot be cleaned up by an old panel callback.
        let operationID = session.exportTransfer?.operationID
        ZStack {
            // Níveis cobertos não recebem cliques nem aparecem para a leitura de tela.
            BoardCanvasView(
                model: model,
                hero: hero,
                filter: filter,
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
                onMove: session.move,
                selection: canvasSelection
            )
            .allowsHitTesting(path.isEmpty && session.restorationPhase == .ready)
            .accessibilityHidden(!path.isEmpty || session.restorationPhase != .ready)

            ForEach(Array(path.enumerated()), id: \.element.id) { index, destination in
                pageBackground(for: destination)
                    .heroLink(destination.id, hero)
                    .zIndex(Double(index * 2 + 1))
                destinationContent(destination)
                    .allowsHitTesting(index == path.count - 1)
                    .accessibilityHidden(index != path.count - 1)
                    .transition(.opacity)
                    .zIndex(Double(index * 2 + 2))
            }
        }
        .ignoresSafeArea()
        .navigationTitle(session.title)
        .navigationSubtitle(breadcrumb)
        .toolbar {
            ToolbarItem(placement: .principal) {
                BoardSwitcherMenu(
                    currentName: session.title,
                    currentRoute: session.route,
                    library: session.registry.library,
                    onNewBoard: { session.actions.newBoard() })
            }
        }
        .focusedSceneValue(session.restorationPhase == .ready ? session.actions : nil)
        .overlay(alignment: .topLeading) {
            FloatingToolbar(
                level: NavigationLevel(path: path), onBack: goBack,
                filter: Binding(get: { session.filter }, set: { session.setNavigation(path: session.path, filter: $0) })
            )
            .padding(12)
            .containerCornerOffset(.top)
            .disabled(session.restorationPhase != .ready)
        }
        .overlay(alignment: .bottom) {
            bottomBar
        }
        .overlay {
            if session.restorationPhase != .ready {
                ProgressView("Restaurando mural…")
                    .padding(20)
                    .glassEffect()
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Restaurando mural")
            }
        }
        .overlay(alignment: .top) {
            if let message = model.lastError ?? session.error {
                ErrorBanner(message: message) { model.lastError = nil }
                    .padding(12)
                    .containerCornerOffset(.top)
                    .transition(errorTransition)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isCanvasFocused)
        .onAppear { isCanvasFocused = true }
        .onKeyPress(.escape) {
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
        .onPasteCommand(of: PasteboardImporter.acceptedTypes) { _ in
            // Lê agora (o conteúdo pode mudar); copia e grava fora do Main Actor.
            let content = PasteboardImporter.read()
            let folder = currentFolderID
            // Texto solto espera a escolha do tipo no popup; nada vira cartão antes disso.
            if case .text(let text) = content {
                pendingPaste = PendingPaste(text: text, folderID: folder)
                return
            }
            let animation = importAnimation
            Task { await session.importPasted(content, into: folder, animation: animation) }
        }
        .sheet(item: $pendingPaste) { paste in
            PasteChoiceSheet(paste: paste, onChoose: { kind in importPaste(paste, as: kind) }, onCancel: cancelPaste)
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return }
            let folder = currentFolderID
            let animation = importAnimation
            Task { await session.importPasted(.files(files), into: folder, animation: animation) }
        }
        .fileImporter(
            isPresented: $session.isImporterPresented,
            allowedContentTypes: PasteboardImporter.importableTypes,
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            Task { await session.importFiles(from: urls) }
        }
        .fileImporter(
            isPresented: $isPackageImporterPresented,
            allowedContentTypes: [.muralPackage],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let source = urls.first else { return }
            importPackage(from: source)
        }
        .fileExporter(
            isPresented: $session.isExporterPresented,
            document: session.exportDocument,
            contentType: .muralPackage,
            defaultFilename: session.title
        ) { result in
            guard let operationID else { return }
            Task { await session.finishSaveCopy(result, operationID: operationID) }
        } onCancellation: {
            guard let operationID else { return }
            Task { await session.finishSaveCopy(nil, operationID: operationID) }
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
            if editingItemID == nil { isCanvasFocused = true }
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
            Group {
                if session.isSelecting {
                    SelectionBar(
                        count: session.currentSelection.count,
                        onDelete: { isConfirmingSelectionDelete = true },
                        onCancel: { session.clearSelection() })
                } else {
                    CreationBar(
                        onNewNote: { createCard(.text) },
                        onNewSticky: { createCard(.sticky) },
                        onNewFolder: newFolderAction,
                        onAddFiles: { session.beginFileImport(folderID: currentFolderID) })
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
        return ItemKind.deleteWarning(forSelection: items) { model.children(of: $0).count }
    }

    private func deleteSelection() {
        withAnimation(reduceMotion ? nil : .smooth) {
            session.deleteSelection()
        }
        isCanvasFocused = true
    }

    /// Folhas de nome (mural e pasta) e avisos de importação.
    private func withDialogs(_ content: some View) -> some View {
        content
            .sheet(isPresented: $isNewBoardPresented) {
                nameSheet(title: "Novo mural", text: $boardNameDraft, actionTitle: "Criar") {
                    createBoard(named: boardNameDraft)
                }
            }
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
            .alert(
                "Não foi possível importar o mural",
                isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
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
                    isNewBoardPresented = false
                    isRenamePresented = false
                    isNewFolderPresented = false
                }
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func handle(_ request: FocusedBoardActionRequest) {
        switch request {
        case .newBoard:
            boardNameDraft = ""
            isNewBoardPresented = true
        case .openMural:
            isPackageImporterPresented = true
        case .rename:
            boardNameDraft = session.title
            isRenamePresented = true
        case .resumeDraft:
            Task {
                guard session.actions.canResumeDraft,
                    let state = try? await session.registry.library.lifecycleState(),
                    state.lifecycle == .draft
                else {
                    session.actions.resumeDraftAvailable = false
                    return
                }
                openWindow(value: BoardRoute.welcomeDraft(state.stableWelcomeID))
            }
        case .promoteDraft:
            Task {
                guard let route = await session.promoteDraft(named: session.title) else { return }
                openWindow(value: route)
                dismiss()
            }
        case .newFolder:
            beginNewFolder()
        case .tileBoard:
            tileBoard()
        }
    }

    private func createBoard(named value: String) {
        isNewBoardPresented = false
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let route = try await session.registry.library.createNamedBoard(
                    name.isEmpty ? "Mural sem título" : name)
                openWindow(value: route)
            } catch {
                importError = "Não foi possível criar o mural: \(error.localizedDescription)"
            }
        }
    }

    private func renameBoard(to value: String) {
        isRenamePresented = false
        Task { await session.rename(to: value) }
    }

    private func importPackage(from source: URL) {
        Task {
            do {
                let result = try await MuralPackageImport.importAsCopy(
                    from: source, using: session.registry.library)
                let importedName = try await session.registry.library.open(result.route)?.manifest.name ?? "Mural"
                openWindow(value: result.route)
                session.successMessage =
                    "Mural ‘\(importedName)’ importado como uma cópia interna. "
                    + "O arquivo original não será alterado."
                switch result.workspaceStatus {
                case .loaded:
                    break
                case .missing:
                    session.warningMessage =
                        "O estado visual do mural importado estava ausente; "
                        + "o conteúdo foi aberto com a visualização padrão."
                case .corrupted(let filename):
                    session.warningMessage =
                        "O estado visual do mural importado estava corrompido (\(filename)); "
                        + "o conteúdo foi aberto com a visualização padrão."
                case .futureSchema(let version):
                    session.warningMessage =
                        "O estado visual do mural importado usa uma versão futura (\(version)); "
                        + "o conteúdo foi aberto com a visualização padrão."
                }
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    // MARK: Níveis

    @ViewBuilder
    private func pageBackground(for destination: Destination) -> some View {
        switch destination {
        case .collection: Theme.canvas
        case .item: Theme.page
        }
    }

    @ViewBuilder
    private func destinationContent(_ destination: Destination) -> some View {
        switch destination {
        case .collection(let id):
            if let folder = model.item(id: id) {
                CollectionView(
                    folder: folder, model: model, session: session, hero: hero, filter: filter, isInfoPresented: $isFolderInfoPresented
                ) {
                    childID in
                    open([.item(childID)])
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
        let extent = BoardLayout.extent(of: model.rootItems)
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
