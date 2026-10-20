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

    private var children: [BoardItem] { model.children(of: folder.id) }

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
                                    itemFrames[item.id] = frame
                                    confirmRestoreIfPossible()
                                }
                                .galleryLane(item.kind.storesFile ? .media : .notes)
                        }
                    }
                }
            }
            .padding(.leading, 104)
            .padding(.trailing, 64)
            .padding(.top, 70)
            .padding(.bottom, 90)
            .scrollTargetLayout()
        }
        .coordinateSpace(name: "collection-content")
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
        .allowsHitTesting(!restoring)
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
            onMoveIntoFolder: session?.moveIntoFolder
        )
        .aspectRatio(BoardLayout.aspectRatio(for: item), contentMode: .fit)
        .cardEmphasis(filter?.emphasis(for: item.kind) ?? 1)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Pasta vazia", systemImage: "rectangle.stack")
        } description: {
            Text("Copie imagens, vídeos, PDFs ou texto e cole aqui com ⌘V, ou arraste para a janela.")
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }

    private func beginRestore() {
        guard let session else { return }
        pendingRestore = session.beginReadingRestore(
            for: folder.id,
            boardID: session.boardID,
            generation: session.generation,
            navigationGeneration: session.navigationGeneration)
        guard case .collection(_, let firstID, _, let fallbackY) = pendingRestore else {
            restoring = false
            session.finishReadingRestore(for: folder.id)
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
        guard restoring, let session,
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
        session.finishReadingRestore(for: folder.id)
    }

    private func captureReadingPosition() {
        guard !restoring, let session,
            session.restorationPhase == .ready,
            session.acceptsPersistence(for: session.boardID, generation: session.generation)
        else { return }
        let frames = itemFrames.map { (id: $0.key, frame: $0.value) }.sorted { $0.frame.minY < $1.frame.minY }
        let position = ReadingPosition.collectionSnapshot(
            folderID: folder.id,
            visibleRect: scrollMetrics.visibleRect,
            itemFrames: frames)
        session.recordReadingPosition(
            position,
            boardID: session.boardID,
            generation: session.generation,
            navigationGeneration: session.navigationGeneration)
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
