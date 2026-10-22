import MuralKit
import SwiftUI

/// Nível 2: o conteúdo de uma pasta. Mídia numa faixa à esquerda, notas e listas
/// numa faixa mais estreita à direita, só com as colunas que os itens ocupam.
struct CollectionView: View {
    let folder: BoardItem
    let model: BoardModel
    let session: BoardWindowSession?
    let hero: HeroContext
    let filter: BoardFilter?
    @Binding var isInfoPresented: Bool
    var onOpenItem: (UUID) -> Void

    @State private var scrollPosition = ScrollPosition(idType: UUID.self)
    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var scrollMetrics = CollectionScrollMetrics()
    @State private var pendingRestore: ReadingPosition?
    @State private var restoring = false
    @State private var presentationToken: ReadingPresentationToken?

    private var children: [BoardItem] { model.children(of: folder.id) }

    /// Seletor de ⌘ só quando esta pasta é o nível de cima (sem um item aberto por cima dela).
    private var selection: CardSelection? {
        guard let session, session.path.last == .collection(folder.id) else { return nil }
        return CardSelection(session: session)
    }

    var body: some View {
        ScrollView {
            Group {
                if children.isEmpty {
                    emptyState
                } else {
                    GalleryLayout {
                        ForEach(children) { item in
                            card(for: item)
                                .id(item.id)
                                .onGeometryChange(for: CGRect.self) { proxy in
                                    proxy.frame(in: .named("collection-content"))
                                } action: { _, frame in
                                    if frame.width > 0, frame.height > 0, frame.origin.x.isFinite,
                                        frame.origin.y.isFinite
                                    {
                                        itemFrames[item.id] = frame
                                    } else {
                                        itemFrames.removeValue(forKey: item.id)
                                    }
                                    confirmRestoreIfPossible()
                                }
                                .galleryLane(item.kind.storesFile || item.kind == .link ? .media : .notes)
                        }
                    }
                }
            }
            .padding(.leading, 104)
            .padding(.trailing, 64)
            .padding(.top, 70)
            .padding(.bottom, 90)
            // O espaço de coordenadas pertence ao conteúdo, não ao viewport.
            .coordinateSpace(name: "collection-content")
            .scrollTargetLayout()
        }
        .scrollPosition($scrollPosition)
        .discreetScrollIndicators()
        .onScrollGeometryChange(for: CollectionScrollMetrics.self) { geometry in
            CollectionScrollMetrics(geometry)
        } action: { _, metrics in
            scrollMetrics = metrics
            confirmRestoreIfPossible()
        }
        .onScrollPhaseChange { _, phase in
            guard phase == .idle else { return }
            captureReadingPosition()
        }
        .overlay(alignment: .topTrailing) {
            FolderInfoButton(folder: folder, children: children, isPresented: $isInfoPresented)
                .padding(12)
                .containerCornerOffset(.top)
        }
        .task(id: folder.id) { beginRestore() }
        .onChange(of: children.map(\.id), initial: true) { _, ids in
            let liveIDs = Set(ids)
            itemFrames = itemFrames.filter { liveIDs.contains($0.key) }
            confirmRestoreIfPossible()
        }
        .allowsHitTesting(!restoring)
        .readingRestoreTimeout(isRestoring: restoring) {
            restoring = false
            if let token = presentationToken { _ = session?.finishReadingRestore(token: token) }
        }
        .accessibilityHidden(restoring)
    }

    private func card(for item: BoardItem) -> some View {
        CardButton(
            item: item,
            model: model,
            hero: hero,
            onOpen: { onOpenItem(item.id) },
            onDelete: session?.delete,
            onMoveToBoard: session?.moveToBoard,
            onMoveIntoFolder: session?.moveIntoFolder,
            selection: selection
        )
        .aspectRatio(BoardLayout.aspectRatio(for: item), contentMode: .fit)
        .cardEmphasis(filter?.emphasis(for: item.kind) ?? 1)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Pasta vazia", systemImage: "rectangle.stack")
        } description: {
            Text("Copie imagens, vídeos, PDFs, links ou texto e cole aqui com ⌘V, ou arraste para a janela.")
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }

    private func beginRestore() {
        guard let session else { return }
        let token = session.readingPresentationToken(for: folder.id)
        presentationToken = token
        pendingRestore = session.beginReadingRestore(token: token)
        guard case .collection(_, let firstID, _, let fallbackY) = pendingRestore else {
            restoring = false
            _ = session.finishReadingRestore(token: token)
            return
        }
        restoring = true
        if let firstID {
            scrollPosition.scrollTo(id: firstID, anchor: .top)
        } else {
            scrollPosition.scrollTo(y: fallbackY)
        }
        confirmRestoreIfPossible()
    }

    private func confirmRestoreIfPossible() {
        guard restoring, let session, let token = presentationToken,
            session.acceptsReadingPresentation(token),
            case .collection = pendingRestore
        else { return }
        guard scrollMetrics.containerSize != .zero, scrollMetrics.contentSize != .zero else { return }
        guard
            let targetY = pendingRestore.flatMap({
                ReadingPosition.collectionTargetY(
                    $0,
                    itemFrame: $0.firstVisibleFrame(in: itemFrames),
                    contentHeight: scrollMetrics.contentSize.height,
                    viewportHeight: scrollMetrics.containerSize.height,
                    contentInsetsTop: scrollMetrics.contentInsets.top,
                    contentInsetsBottom: scrollMetrics.contentInsets.bottom)
            })
        else { return }
        if abs(scrollMetrics.visibleRect.minY - targetY) > 1 {
            scrollPosition.scrollTo(y: targetY)
            return
        }
        restoring = false
        _ = session.finishReadingRestore(token: token)
    }

    private func captureReadingPosition() {
        guard !restoring, let session, let token = presentationToken,
            session.acceptsReadingPresentation(token),
            session.restorationPhase == .ready
        else { return }
        let frames = itemFrames.map { (id: $0.key, frame: $0.value) }.sorted { $0.frame.minY < $1.frame.minY }
        let position = ReadingPosition.collectionSnapshot(
            folderID: folder.id,
            visibleRect: scrollMetrics.visibleRect,
            itemFrames: frames)
        session.recordReadingPosition(position, token: token)
    }
}

private struct CollectionScrollMetrics: Equatable {
    var contentOffset: CGPoint = .zero
    var containerSize: CGSize = .zero
    var contentSize: CGSize = .zero
    var contentInsets: EdgeInsets = EdgeInsets()
    var visibleRect: CGRect = .zero

    init() {}

    init(_ geometry: ScrollGeometry) {
        contentOffset = geometry.contentOffset
        containerSize = geometry.containerSize
        contentSize = geometry.contentSize
        contentInsets = geometry.contentInsets
        visibleRect = geometry.visibleRect
    }
}

extension ReadingPosition {
    fileprivate var firstVisibleItemID: UUID? {
        guard case .collection(_, let id, _, _) = self else { return nil }
        return id
    }

    fileprivate func firstVisibleFrame(in frames: [UUID: CGRect]) -> CGRect? {
        guard let firstVisibleItemID else { return nil }
        return frames[firstVisibleItemID]
    }
}
