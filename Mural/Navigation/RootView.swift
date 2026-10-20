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

    private var navigationAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.45)
    }

    var body: some View {
        ZStack {
            BoardCanvasView(model: model, hero: hero, filter: filter, onOpen: open, onAdd: { commands.isImporterPresented = true })

            ForEach(Array(path.enumerated()), id: \.element.id) { index, destination in
                pageBackground(for: destination)
                    .heroLink(destination.id, hero)
                    .zIndex(Double(index * 2 + 1))
                destinationContent(destination)
                    .transition(.opacity)
                    .zIndex(Double(index * 2 + 2))
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            GlassToolbar(canGoBack: !path.isEmpty, onBack: goBack, filter: $filter)
                .padding(.top, 34)
                .padding(.leading, 14)
        }
        .overlay(alignment: .top) { errorBanner }
        .focusable()
        .focusEffectDisabled()
        .focused($isCanvasFocused)
        .onAppear { isCanvasFocused = true }
        .onKeyPress(.escape) {
            guard !path.isEmpty else { return .ignored }
            goBack()
            return .handled
        }
        .onPasteCommand(of: PasteboardImporter.acceptedTypes) { _ in
            withAnimation(.smooth) { _ = PasteboardImporter.paste(into: model, parentID: currentFolderID) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            withAnimation(.smooth) { _ = model.importFiles(files, into: currentFolderID) }
        }
        .fileImporter(
            isPresented: $commands.isImporterPresented,
            allowedContentTypes: [.image, .movie, .pdf, .plainText, .text],
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
                CollectionView(folder: folder, model: model, hero: hero, filter: filter) { childID in
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

    private func open(_ destinations: [Destination]) {
        withAnimation(navigationAnimation) { path.append(contentsOf: destinations) }
    }

    private func goBack() {
        guard !path.isEmpty else { return }
        withAnimation(navigationAnimation) { _ = path.removeLast() }
        isCanvasFocused = true
    }

    // MARK: Erros

    @ViewBuilder
    private var errorBanner: some View {
        if let message = model.lastError {
            HStack(spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                Button("Fechar", systemImage: "xmark") { model.lastError = nil }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            .padding(.top, 34)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
