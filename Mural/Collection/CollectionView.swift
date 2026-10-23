import MuralKit
import SwiftUI

/// Nível 2: o conteúdo de uma pasta, em colunas. Mídia numa faixa à esquerda, notas e listas
/// numa faixa mais estreita à direita, só com as colunas que os itens ocupam. Os post-its
/// podem ser arrastados: ficam soltos por cima das colunas, onde o ponteiro os largou.
struct CollectionView: View {
    let folder: BoardItem
    let model: BoardModel
    let session: BoardWindowSession?
    let hero: HeroContext
    let filter: BoardFilter?
    var colorFilter: TagColor? = nil
    /// "Renomear…" no menu das pastas de dentro desta.
    var onRenameFolder: ((UUID) -> Void)? = nil
    var onOpenItem: (UUID) -> Void

    @State private var scrollPosition = ScrollPosition(idType: UUID.self)
    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var scrollMetrics = CollectionScrollMetrics()
    @State private var pendingRestore: ReadingPosition?
    @State private var restoring = false
    @State private var presentationToken: ReadingPresentationToken?
    /// Post-it arrastado e quanto andou, em pontos do conteúdo.
    @State private var stickyDrag: StickyDrag?
    /// Área dos cartões (a das colunas e a dos post-its soltos), no espaço do conteúdo.
    @State private var placementArea: CGRect = .zero
    /// Volta sozinho a falso, inclusive quando o gesto é cancelado sem `onEnded`.
    @GestureState private var isDraggingSticky = false

    /// Nome do espaço de coordenadas em que os quadros e os arrastos são medidos. `nonisolated`: as medições
    /// (`onGeometryChange`) leem o nome fora do MainActor.
    private nonisolated static let space = "collection-content"

    private var children: [BoardItem] { model.children(of: folder.id) }
    /// Os cartões das colunas: tudo, menos os post-its largados num lugar livre da pasta.
    private var columnItems: [BoardItem] { children.filter { !$0.isPlacedInFolder } }
    /// Os post-its soltos, na ordem da lista: o último fica por cima.
    private var placedStickies: [BoardItem] { model.board.placedStickies(in: folder.id) }
    /// O post-it arrastado ainda está nas colunas: elas passam por cima dos soltos até ele ser largado.
    private var isDraggingFromColumns: Bool {
        guard let id = stickyDrag?.id else { return false }
        return columnItems.contains { $0.id == id }
    }

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
                    ZStack(alignment: .topLeading) {
                        GalleryLayout {
                            ForEach(columnItems) { item in
                                measuredCard(for: item)
                                    .galleryLane(item.kind.storesFile || item.kind == .link ? .media : .notes)
                                    .zIndex(stickyDrag?.id == item.id ? 1 : 0)
                            }
                        }
                        .zIndex(isDraggingFromColumns ? 1 : 0)
                        StickyPlacementLayout {
                            ForEach(placedStickies) { item in
                                let place = item.folderPosition ?? .zero
                                measuredCard(for: item)
                                    .stickyPlacement(CGPoint(x: place.x, y: place.y))
                                    .zIndex(stickyDrag?.id == item.id ? 1 : 0)
                            }
                        }
                    }
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(Self.space))
                    } action: { _, area in
                        placementArea = area
                    }
                }
            }
            .padding(.leading, 104)
            .padding(.trailing, 64)
            .padding(.top, 70)
            .padding(.bottom, 90)
            // Shift + arrastar no vazio marca os cartões cruzados, medidos no mesmo espaço do conteúdo.
            .marqueeSelecting(in: Self.space, selection: selection) { itemFrames }
            // O espaço de coordenadas pertence ao conteúdo, não ao viewport.
            .coordinateSpace(name: Self.space)
            .scrollTargetLayout()
        }
        .scrollPosition($scrollPosition)
        .discreetScrollIndicators()
        .onScrollGeometryChange(for: CollectionScrollMetrics.self) { geometry in
            CollectionScrollMetrics(geometry)
        } action: { _, metrics in
            scrollMetrics = metrics
            recordNewStickyPlace(visibleRect: metrics.visibleRect)
            confirmRestoreIfPossible()
        }
        // A área pode ser medida depois da primeira leitura da rolagem, e sem rolar não haveria outra.
        .onChange(of: placementArea) { recordNewStickyPlace(visibleRect: scrollMetrics.visibleRect) }
        .onScrollPhaseChange { _, phase in
            guard phase == .idle else { return }
            captureReadingPosition()
        }
        .task(id: folder.id) { beginRestore() }
        .onChange(of: children.map(\.id), initial: true) { _, ids in
            let liveIDs = Set(ids)
            itemFrames = itemFrames.filter { liveIDs.contains($0.key) }
            confirmRestoreIfPossible()
        }
        // Gesto cancelado sem `onEnded`: desfaz o arrasto. Fica para a volta seguinte do laço
        // principal, para não atropelar o `onEnded` quando ele vier.
        .onChange(of: isDraggingSticky) { _, active in
            guard !active else { return }
            Task { @MainActor in stickyDrag = nil }
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
            onSetColorTag: { session?.setColorTag($1, for: $0) },
            onMoveUp: session?.moveUp,
            onRename: onRenameFolder,
            onToggleReminder: { id in Task { await session?.toggleReminder(id) } },
            selection: selection
        )
        .aspectRatio(BoardLayout.aspectRatio(for: item), contentMode: .fit)
        .cardEmphasis(BoardFilter.emphasis(for: item, kind: filter, color: colorFilter))
        .highPriorityGesture(stickyMoveGesture(for: item), isEnabled: item.kind == .sticky)
        .offset(stickyOffset(for: item))
    }

    /// O cartão com o id de rolagem e a medição do quadro dele no espaço do conteúdo. O arrasto (`.offset`) vem antes
    /// da medição, então `itemFrames` guarda o quadro sem ele.
    private func measuredCard(for item: BoardItem) -> some View {
        card(for: item)
            .id(item.id)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(Self.space))
            } action: { _, frame in
                if frame.width > 0, frame.height > 0, frame.origin.x.isFinite, frame.origin.y.isFinite {
                    itemFrames[item.id] = frame
                } else {
                    itemFrames.removeValue(forKey: item.id)
                }
                confirmRestoreIfPossible()
            }
    }

    /// Quanto o post-it arrastado já andou; os outros cartões ficam parados.
    private func stickyOffset(for item: BoardItem) -> CGSize {
        stickyDrag?.id == item.id ? stickyDrag?.translation ?? .zero : .zero
    }

    /// Arrasto de um post-it da pasta. O clique simples continua abrindo: o gesto só começa depois de 4 pontos de
    /// movimento e, por ter prioridade sobre o botão, impede que o arrasto abra o post-it. A posição só é gravada ao
    /// soltar, sem animação: o post-it fica onde o ponteiro o deixou, solto por cima das colunas e dos outros cartões
    /// (soltar sobre uma subpasta não o guarda nela). Os outros tipos de cartão não se movem.
    private func stickyMoveGesture(for item: BoardItem) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .updating($isDraggingSticky) { _, isDragging, _ in isDragging = true }
            .onChanged { value in
                stickyDrag = StickyDrag(id: item.id, translation: value.translation)
            }
            .onEnded { value in
                guard let frame = itemFrames[item.id], placementArea.width > 0 else {
                    stickyDrag = nil
                    return
                }
                // Canto do post-it onde o ponteiro o deixou, medido na área dos cartões.
                let origin = CGPoint(
                    x: frame.minX + value.translation.width - placementArea.minX,
                    y: frame.minY + value.translation.height - placementArea.minY)
                let place = StickyPlacement.position(forOrigin: origin, width: placementArea.width)
                let target = BoardPoint(x: place.x, y: place.y)
                // Sem animação: o post-it já está onde o ponteiro o deixou.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    if let session { session.placeInFolder(item.id, at: target) } else { model.placeInFolder(item.id, at: target) }
                    stickyDrag = nil
                }
            }
    }

    /// O post-it novo nasce no meio do que está à vista, já na coordenada do lugar na pasta (a da área dos cartões).
    private func recordNewStickyPlace(visibleRect: CGRect) {
        guard placementArea.width > 0 else { return }
        session?.recordCollectionVisibleCenter(
            folder.id, visibleRect: StickyPlacement.visibleRectForNewSticky(visibleRect, area: placementArea))
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

/// Post-it em arrasto e quanto já andou desde que o gesto começou, em pontos do conteúdo.
private struct StickyDrag: Equatable {
    var id: UUID
    var translation: CGSize
}
