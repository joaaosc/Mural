import MuralKit
import SwiftUI

/// Nível 2: o conteúdo de uma pasta, em colunas. Mídia numa faixa à esquerda, notas e listas
/// numa faixa mais estreita à direita, só com as colunas que os itens ocupam. Os post-its
/// podem ser arrastados: ficam soltos por cima das colunas, onde o ponteiro os largou, ou
/// entram na subpasta sobre a qual forem largados.
struct CollectionView: View {
    let folder: BoardItem
    let model: BoardModel
    let session: BoardWindowSession?
    let hero: HeroContext
    let filter: BoardFilter?
    var colorFilter: TagColor? = nil
    /// "Renomear…" no menu dos cartões desta pasta.
    var onRename: ((UUID) -> Void)? = nil
    /// "Adicionar/Editar legenda…" no menu dos cartões desta pasta.
    var onEditCaption: ((UUID) -> Void)? = nil
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

    /// Seletor de ⌘ só quando esta pasta é o nível de cima (sem um item aberto por cima dela).
    private var selection: CardSelection? {
        guard let session, session.path.last == .collection(folder.id) else { return nil }
        return CardSelection(session: session)
    }

    var body: some View {
        let children = model.children(of: folder.id)
        // Os cartões das colunas: tudo, menos os post-its largados num lugar livre da pasta.
        // Os post-its soltos são derivados da mesma lista já memoizada: não percorremos o board inteiro
        // nem fazemos uma segunda filtragem independente para descobrir os dois grupos.
        let (columnItems, placedStickies) = splitChildren(children)
        let isDraggingFromColumns =
            stickyDrag.map { drag in
                columnItems.contains { $0.id == drag.id }
            } ?? false

        ScrollView {
            Group {
                if children.isEmpty {
                    emptyState
                } else {
                    ZStack(alignment: .topLeading) {
                        GalleryLayout {
                            ForEach(columnItems) { item in
                                measuredCard(for: item, columnItems: columnItems)
                                    .galleryLane(item.kind.storesFile || item.kind == .link ? .media : .notes)
                                    .zIndex(stickyDrag?.id == item.id ? 1 : 0)
                            }
                        }
                        .zIndex(isDraggingFromColumns ? 1 : 0)
                        StickyPlacementLayout {
                            ForEach(placedStickies) { item in
                                let place = item.folderPosition ?? .zero
                                measuredCard(for: item, columnItems: columnItems)
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

    private func splitChildren(_ children: [BoardItem]) -> (columnItems: [BoardItem], placedStickies: [BoardItem]) {
        var columnItems: [BoardItem] = []
        var placedStickies: [BoardItem] = []
        columnItems.reserveCapacity(children.count)
        placedStickies.reserveCapacity(children.count)
        for child in children {
            if child.isPlacedInFolder {
                placedStickies.append(child)
            } else {
                columnItems.append(child)
            }
        }
        return (columnItems, placedStickies)
    }

    private func card(for item: BoardItem, columnItems: [BoardItem]) -> some View {
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
            onRename: onRename,
            onEditCaption: onEditCaption,
            onToggleReminder: { id in Task { await session?.toggleReminder(id) } },
            onToggleMusic: { id in Task { await session?.toggleMusic(id) } },
            musicPhase: item.kind == .music ? session?.musicPhase(of: item.id) ?? .idle : .idle,
            selection: selection
        )
        .aspectRatio(BoardLayout.aspectRatio(for: item), contentMode: .fit)
        .cardEmphasis(BoardFilter.emphasis(for: item, kind: filter, color: colorFilter))
        .dropTargetHighlight(stickyDrag?.tracker.target == item.id)
        .highPriorityGesture(stickyMoveGesture(for: item, columnItems: columnItems), isEnabled: item.kind == .sticky)
        .offset(stickyOffset(for: item))
    }

    /// O cartão com o id de rolagem e a medição do quadro dele no espaço do conteúdo. O arrasto (`.offset`) vem antes
    /// da medição, então `itemFrames` guarda o quadro sem ele.
    private func measuredCard(for item: BoardItem, columnItems: [BoardItem]) -> some View {
        card(for: item, columnItems: columnItems)
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
    /// soltar, sem animação: o post-it fica onde o ponteiro o deixou, solto por cima das colunas e dos outros cartões.
    /// Soltar sobre uma subpasta (destacada antes de soltar) o guarda nela, desde que o domínio aceite o destino: ele
    /// sai desta pasta e perde o lugar solto. Os outros tipos de cartão não se movem.
    private func stickyMoveGesture(for item: BoardItem, columnItems: [BoardItem]) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .updating($isDraggingSticky) { _, isDragging, _ in isDragging = true }
            .onChanged { value in
                stickyDrag = drag(of: item, moved: value, columnItems: columnItems)
            }
            .onEnded { value in
                // Decide pelo ponto em que o botão foi solto: num arrasto rápido ele pode não ter chegado num
                // `onChanged`, e o destino anotado estaria atrasado.
                if let folderID = drag(of: item, moved: value, columnItems: columnItems).tracker.target {
                    store(item, in: folderID)
                    return
                }
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

    /// O arrasto de `item` com o ponteiro onde `value` o deixou. No primeiro movimento, anota as subpastas que podem
    /// guardar o post-it e a que já estava sob o ponteiro (ela só vira destino depois que o ponteiro sai dela uma
    /// vez); depois, só acompanha o ponteiro.
    private func drag(of item: BoardItem, moved value: DragGesture.Value, columnItems: [BoardItem]) -> StickyDrag {
        var current: StickyDrag
        if let existing = stickyDrag, existing.id == item.id {
            current = existing
        } else {
            let accepted = acceptedSubfolders(for: item, among: columnItems)
            current = StickyDrag(
                id: item.id, translation: .zero,
                tracker: FolderDropTracker(startFolder: subfolder(at: value.startLocation, among: accepted)),
                acceptedFolders: accepted)
        }
        current.translation = value.translation
        current.tracker.update(folderUnderPointer: subfolder(at: value.location, among: current.acceptedFolders))
        return current
    }

    /// As subpastas desta pasta (as das colunas) que o domínio aceita como destino do post-it.
    private func acceptedSubfolders(for item: BoardItem, among columnItems: [BoardItem]) -> [UUID] {
        let accepted = Set(model.folderDestinations(for: item.id).map(\.id))
        return columnItems.filter { $0.kind == .folder && accepted.contains($0.id) }.map(\.id)
    }

    /// Subpasta sob um ponto do conteúdo, só entre as aceitas: soltar nunca é recusado em silêncio.
    private func subfolder(at point: CGPoint, among accepted: [UUID]) -> UUID? {
        StickyPlacement.folder(under: point, frames: itemFrames, among: accepted)
    }

    /// Guarda o post-it na subpasta: ele sai desta pasta e entra nas colunas da subpasta, sem animação.
    private func store(_ item: BoardItem, in folderID: UUID) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let session {
                session.moveIntoFolder(item.id, folderID: folderID)
            } else {
                model.moveIntoFolder(item.id, folderID: folderID)
            }
            stickyDrag = nil
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
    /// Acompanha a subpasta que guardaria o post-it se ele fosse solto agora.
    var tracker: FolderDropTracker
    /// Subpastas desta pasta que o domínio aceita como destino, fixadas no começo do arrasto.
    var acceptedFolders: [UUID]
}
