import MuralKit
import SwiftUI
import UniformTypeIdentifiers

/// Empilha os três níveis (mural → pasta → item) num único ZStack, para que cada
/// nível cresça a partir do cartão clicado, e recebe ⌘V, arrastar e importar.
struct RootView: View {
    let model: BoardModel
    @Bindable var commands: AppCommandsState

    @State private var path: [Destination] = []
    @State private var filter: BoardFilter?
    @State private var isFolderInfoPresented = false
    @FocusState private var isCanvasFocused: Bool
    @Namespace private var heroNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    /// Título da janela: o nome do que está aberto na frente.
    private var windowTitle: String {
        guard let id = path.last?.id, let item = model.item(id: id) else { return "Mural" }
        return item.title
    }

    private var navigationAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.45)
    }

    var body: some View {
        ZStack {
            // Níveis cobertos não recebem cliques nem aparecem para a leitura de tela.
            BoardCanvasView(model: model, hero: hero, filter: filter, onOpen: open, onAdd: { commands.isImporterPresented = true })
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
        .navigationTitle(windowTitle)
        .overlay(alignment: .topLeading) {
            FloatingToolbar(level: NavigationLevel(path: path), onBack: goBack, filter: $filter)
                .padding(12)
                .containerCornerOffset(.top)
        }
        .overlay(alignment: .top) {
            if let message = model.lastError {
                ErrorBanner(message: message) { model.lastError = nil }
                    .padding(12)
                    .containerCornerOffset(.top)
                    .transition(.move(edge: .top).combined(with: .opacity))
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
            withAnimation(.smooth) { PasteboardImporter.paste(into: model, parentID: currentFolderID) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            withAnimation(.smooth) { _ = model.importFiles(files, into: currentFolderID) }
        }
        .fileImporter(
            isPresented: $commands.isImporterPresented,
            allowedContentTypes: PasteboardImporter.importableTypes,
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            withAnimation(.smooth) {
                _ = SecurityScopedAccess.withAccess(to: urls) { model.importFiles(urls, into: currentFolderID) }
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
            path.append(contentsOf: newLevels)
            filter = nil
        }
        isFolderInfoPresented = false
        isCanvasFocused = true
    }

    private func goBack() {
        guard !path.isEmpty else { return }
        withAnimation(navigationAnimation) {
            _ = path.removeLast()
            filter = nil
        }
        isFolderInfoPresented = false
        isCanvasFocused = true
    }
}
