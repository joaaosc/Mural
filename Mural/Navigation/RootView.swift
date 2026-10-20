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
    @FocusState private var isCanvasFocused: Bool
    @Namespace private var heroNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        ZStack {
            // Níveis cobertos não recebem cliques nem aparecem para a leitura de tela.
            BoardCanvasView(
                model: model,
                hero: hero,
                filter: filter,
                zoom: session.zoom,
                onOpen: open,
                onAdd: { session.isImporterPresented = true },
                boardID: session.boardID,
                generation: session.generation,
                onCanvasGeometryReady: { viewport, contentSize in session.restoreCanvas(viewport: viewport, contentSize: contentSize) },
                onCanvasChange: { boardID, generation, state in
                    session.recordCanvas(boardID: boardID, generation: generation, state: state)
                }
            )
            .allowsHitTesting(path.isEmpty)
            .accessibilityHidden(!path.isEmpty)

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
        .focusedSceneValue(path.isEmpty ? session.actions : nil)
        .overlay(alignment: .topLeading) {
            FloatingToolbar(
                level: NavigationLevel(path: path), onBack: goBack,
                filter: Binding(get: { session.filter }, set: { session.setNavigation(path: session.path, filter: $0) })
            )
            .padding(12)
            .containerCornerOffset(.top)
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
            if isFolderInfoPresented {
                isFolderInfoPresented = false
                return .handled
            }
            guard !path.isEmpty else { return .ignored }
            goBack()
            return .handled
        }
        .onPasteCommand(of: PasteboardImporter.acceptedTypes) { _ in
            withAnimation(importAnimation) {
                PasteboardImporter.paste(into: model, parentID: currentFolderID)
            }
            session.captureBoardIfNeeded()
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            withAnimation(importAnimation) { _ = model.importFiles(files, into: currentFolderID) }
            session.captureBoardIfNeeded()
        }
        .fileImporter(
            isPresented: $session.isImporterPresented,
            allowedContentTypes: PasteboardImporter.importableTypes,
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            withAnimation(importAnimation) {
                _ = SecurityScopedAccess.withAccess(to: urls) { model.importFiles(urls, into: currentFolderID) }
            }
            session.captureBoardIfNeeded()
        }
        .onChange(of: model.board) { _, _ in
            session.captureBoardIfNeeded()
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
                CollectionView(folder: folder, model: model, hero: hero, filter: filter, isInfoPresented: $isFolderInfoPresented) {
                    childID in
                    open([.item(childID)])
                }
            }
        case .item(let id):
            if let item = model.item(id: id) {
                ItemDetailView(item: item, model: model, onClose: goBack)
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

    private func goBack() {
        guard !path.isEmpty else { return }
        withAnimation(navigationAnimation) {
            session.setNavigation(path: Array(session.path.dropLast()), filter: nil)
        }
        isFolderInfoPresented = false
        isCanvasFocused = true
    }
}
