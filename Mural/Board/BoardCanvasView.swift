import AppKit
import MuralKit
import SwiftUI

/// Nível 1: o mural livre, com rolagem nos dois sentidos e zoom.
struct BoardCanvasView: View {
    let model: BoardModel
    let hero: HeroContext
    let filter: BoardFilter?
    /// Destaque por cor da barra; some ao trocar de nível, como o filtro de tipo.
    var colorFilter: TagColor? = nil
    @Bindable var zoom: CanvasZoomController
    var onOpen: ([Destination]) -> Void
    var boardID: BoardID
    var generation: UInt64
    var onCanvasGeometryReady: (BoardID, UInt64, CanvasScrollMetrics) -> Void = { _, _, _ in }
    var onCanvasChange: (BoardID, UInt64, CanvasWorkspaceState) -> Void = { _, _, _ in }
    var onDelete: ((UUID) -> Void)? = nil
    var onMoveToBoard: ((UUID) -> Void)? = nil
    var onMoveIntoFolder: ((UUID, UUID) -> Void)? = nil
    var onSetColorTag: ((UUID, TagColor?) -> Void)? = nil
    var onToggleReminder: ((UUID) -> Void)? = nil
    var onToggleMusic: ((UUID) -> Void)? = nil
    var musicPhase: ((UUID) -> MusicCardPhase)? = nil
    var onMove: ((UUID, BoardPoint) -> Void)? = nil
    var onMoveGroup: (([UUID: BoardPoint], [UUID: BoardPoint]) -> Void)? = nil
    var onMoveGroupIntoFolder: (([UUID: BoardPoint], UUID) -> Void)? = nil
    /// Grava o tamanho de um post-it, arrastando o canto ou pelo menu (`nil` volta ao padrão). `nil` fala direto com o modelo,
    /// como `onMove`.
    var onResize: ((UUID, BoardSize?) -> Void)? = nil
    /// Grava posição e tamanho de uma vez, quando o arrasto é por um canto que não é o de baixo à direita (a posição muda junto).
    /// `nil` fala direto com o modelo.
    var onResizeFrame: ((UUID, BoardSize?, BoardPoint) -> Void)? = nil
    var onFreeTextEdit: ((UUID) -> Void)? = nil
    var onFreeTextMove: ((UUID, BoardPoint) -> Void)? = nil
    /// O mesmo de `onResize` para um texto livre.
    var onFreeTextResize: ((UUID, BoardSize?) -> Void)? = nil
    /// O mesmo de `onResizeFrame` para um texto livre.
    var onFreeTextResizeFrame: ((UUID, BoardSize?, BoardPoint) -> Void)? = nil
    var onFreeTextDelete: ((UUID) -> Void)? = nil
    /// "Renomear…" no menu de qualquer cartão.
    var onRename: ((UUID) -> Void)? = nil
    /// "Adicionar/Editar legenda…" no menu de qualquer cartão.
    var onEditCaption: ((UUID) -> Void)? = nil
    /// Seletor de ⌘ dos cartões soltos; a prévia de pasta fica de fora.
    var selection: CardSelection? = nil

    @State private var hoveredFolder: UUID?
    /// Pasta sob o ponteiro agora, atualizada mesmo durante um arrasto; vira o foco ao soltar.
    @State private var pointerFolder: UUID?
    /// Cartão arrastado e quanto andou, em pontos do mural (sem zoom).
    @State private var drag: CardDrag?
    /// Texto livre arrastado e quanto andou, em pontos do mural (sem zoom).
    @State private var freeTextDrag: FreeTextDrag?
    /// Post-it, foto ou texto livre com o ponteiro em cima: é quando a alça de redimensionar aparece.
    @State private var hoveredResizable: ResizeDrag.Target?
    /// Redimensionamento em andamento e o tamanho que o arrasto do canto dá ao elemento agora, em pontos do mural.
    @State private var resizing: ResizeDrag?
    /// Cartão encolhendo em direção à pasta onde está sendo guardado; sai do mural no fim.
    @State private var storing: UUID?
    /// Retângulo de Shift + arrastar aberto: a prévia de pasta não aparece enquanto ele existe.
    @State private var isMarqueeActive = false
    /// O binding bidirecional do scroll pertence à identidade desta view. Mantê-lo
    /// fora do controlador observável impede um ciclo AttributeGraph → setter →
    /// nova avaliação durante restaurações programáticas.
    @State private var scrollPosition = ScrollPosition()
    /// Retângulo lógico com margem de pré-carregamento usado para não construir cartões fora da viewport.
    @State private var renderViewport = CGRect.zero
    /// Cache local que evita repetir o culling enquanto seus determinantes não mudam.
    @State private var cullingCache = CanvasRenderCulling.Cache()
    /// Volta sozinho a falso, inclusive quando o gesto é cancelado sem `onEnded`.
    @GestureState private var isDragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityEnabled) private var accessibilityEnabled
    /// O Live Share do app; `nil` fora dele (nas prévias, por exemplo).
    @Environment(LiveShareController.self) private var liveShare: LiveShareController?

    /// Folga em volta dos cartões, para o mural não terminar colado no último.
    private static let margin: CGFloat = 240
    /// Nome do espaço de coordenadas em que os arrastos são medidos.
    private static let space = "mural"

    /// O que está em destaque agora: pasta em foco, cartão arrastado, pasta de destino e filtro.
    private var focus: BoardFocus {
        BoardFocus(
            hoveredFolder: hoveredFolder, dragged: drag?.id, dropTarget: drag?.tracker?.candidate,
            dropArmed: drag?.tracker?.isArmed ?? false, filter: filter, colorFilter: colorFilter)
    }

    var body: some View {
        let items = model.rootItems
        let freeTexts = model.freeTexts
        // O culling, o desenho e a extensão usam os mesmos snapshots de tamanho quando a viewport
        // já foi medida. Isso também deixa `rootExtent` aproveitar os mapas sem materializá-los duas vezes.
        let itemSizes = displayedSizes(for: items, when: renderViewport)
        let freeTextSizes = displayedSizes(for: freeTexts, when: renderViewport)
        let itemSizeOverride = displayedSizeOverride(for: .item, when: renderViewport)
        let freeTextSizeOverride = displayedSizeOverride(for: .freeText, when: renderViewport)
        let extent = model.rootExtent
        let viewport = zoom.viewport
        // Como num quadro branco: sempre uma tela de folga à direita e embaixo, para o
        // zoom poder manter parado o ponto sob os dedos (ou o centro da janela).
        let slack = CGSize(width: viewport.width / zoom.zoom, height: viewport.height / zoom.zoom)
        let contentSize = CGSize(
            width: max(extent.width + Self.margin, slack.width) + slack.width,
            height: max(extent.height + Self.margin, slack.height) + slack.height
        )
        let layoutSize = CGSize(width: contentSize.width * zoom.zoom, height: contentSize.height * zoom.zoom)
        let currentFocus = focus
        let alwaysRendered = Set(
            [drag?.id, storing, hoveredFolder, pointerFolder, drag?.tracker?.candidate, resizing?.target.itemID].compactMap { $0 }
        )
        .union(drag?.origins.keys.map { $0 } ?? [])
        let alwaysRenderedFreeTexts = Set(
            [
                freeTextDrag?.id,
                hoveredResizable?.freeTextID,
                resizing?.target.freeTextID,
            ].compactMap { $0 })
        // A seleção por retângulo usa o mapa geométrico completo capturado no início
        // do gesto; os cartões fora da viewport não precisam entrar na árvore visual.
        let forceAll = accessibilityEnabled
        let cullingKey = CanvasRenderCulling.Key(
            boardID: boardID,
            generation: generation,
            boardRevision: model.boardRevision,
            renderViewport: renderViewport,
            alwaysRendered: alwaysRendered,
            alwaysRenderedFreeTexts: alwaysRenderedFreeTexts,
            forceAll: forceAll,
            resizingItemID: resizing.flatMap { target in
                guard case .item(let id) = target.target else { return nil }
                return id
            },
            resizingFreeTextID: resizing?.target.freeTextID,
            resizingSize: resizing?.size)
        let rendered = cullingCache.content(
            for: cullingKey,
            items: items,
            freeTexts: freeTexts,
            viewport: renderViewport,
            alwaysRendered: alwaysRendered,
            alwaysRenderedFreeTexts: alwaysRenderedFreeTexts,
            forceAll: forceAll,
            itemSizes: itemSizes,
            freeTextSizes: freeTextSizes,
            itemSizeOverride: itemSizeOverride,
            freeTextSizeOverride: freeTextSizeOverride)
        let renderedItems = rendered.items
        let renderedFreeTexts = rendered.freeTexts

        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                ForEach(renderedItems) { item in
                    let itemEmphasis = currentFocus.emphasis(for: item)
                    let itemSize = displayedSize(for: item, cachedSizes: itemSizes, override: itemSizeOverride)
                    let shrink = hoverShrinkState(for: item, size: itemSize)
                    cardGroup(for: item, size: itemSize, focus: currentFocus)
                        .cardEmphasis(itemEmphasis)
                        // Sobre uma pasta: encolhe em direção ao ponteiro para a pasta continuar visível.
                        .modifier(
                            FolderHoverShrink(
                                progress: shrink.isShrunk ? 1 : 0, anchor: shrink.anchor, minScale: shrink.minScale,
                                reduceMotion: reduceMotion)
                        )
                        .animation(reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.35), value: shrink.isShrunk)
                        // Guardado numa pasta: encolhe em direção a ela e some antes de sair do mural.
                        .scaleEffect(storing == item.id ? 0.1 : 1, anchor: storeAnchor(for: item, size: itemSize))
                        .opacity(storing == item.id ? 0 : 1)
                        .offset(offset(for: item))
                        .zIndex(drag?.origins[item.id] != nil ? 4 : currentFocus.layer(for: item, emphasis: itemEmphasis))
                }
                ForEach(renderedFreeTexts) { freeText in
                    let freeTextSize = displayedSize(for: freeText, cachedSizes: freeTextSizes, override: freeTextSizeOverride)
                    BoardFreeTextView(
                        freeText: freeText,
                        size: freeTextSize,
                        onEdit: { onFreeTextEdit?(freeText.id) },
                        onDelete: { onFreeTextDelete?(freeText.id) },
                        onResize: { size in
                            withAnimation(reduceMotion ? nil : .smooth) { commitResize(.freeText(freeText.id), to: size) }
                        }
                    )
                    // A alça vem antes do gesto: o arrasto que começa nela chega ao gesto do texto, que decide pelo canto.
                    .resizeHandle(isVisible: showsResizeHandle(for: .freeText(freeText.id)), zoom: zoom.zoom)
                    .resizeCornerPointer(size: freeTextSize, zoom: zoom.zoom, isEnabled: allowsResizeCornerPointer)
                    .onHover { inside in resizableHoverChanged(.freeText(freeText.id), inside: inside) }
                    .cardEmphasis(hoveredFolder == nil ? 1 : 0.3)
                    .offset(freeTextOffset(for: freeText))
                    .zIndex(hoveredFolder == nil ? 100 : 0)
                    .highPriorityGesture(freeTextMoveGesture(for: freeText))
                }
            }
            .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
            // Shift + arrastar no vazio marca os cartões cruzados; o contorno fica com um ponto na tela.
            .marqueeSelecting(
                in: Self.space, selection: selection, lineWidth: 1 / zoom.zoom, isActive: $isMarqueeActive
            ) {
                cardFrames(of: items, displayedSizes: itemSizes, sizeOverride: itemSizeOverride)
            }
            // Live Share: o que as outras pessoas fazem neste mural (cursores, arrastos, cartões abertos), em pontos do mural, e o
            // ponteiro daqui para elas. Fora de um Live Share nada é desenhado nem enviado.
            .overlay(alignment: .topLeading) {
                LivePresenceLayer(boardID: boardID, model: model, zoom: zoom.zoom)
            }
            .onContinuousHover(coordinateSpace: .named(Self.space)) { phase in
                switch phase {
                case .active(let point): liveShare?.pointerMoved(to: point, in: boardID)
                case .ended: liveShare?.pointerMoved(to: nil, in: boardID)
                }
            }
            // Os arrastos medem neste espaço, em pontos do mural, sem o zoom.
            .coordinateSpace(.named(Self.space))
            .scaleEffect(zoom.zoom, anchor: .topLeading)
            .frame(width: layoutSize.width, height: layoutSize.height, alignment: .topLeading)
            // Escala visual da pinça, ancorada no ponto entre os dedos.
            .scaleEffect(zoom.liveScale, anchor: unitPoint(zoom.liveAnchor, in: layoutSize))
        }
        .scrollPosition($scrollPosition)
        .discreetScrollIndicators([.horizontal, .vertical])
        .background { SurfaceFill(.board) }
        .onScrollGeometryChange(for: CanvasScrollMetrics.self) { geometry in
            CanvasScrollMetrics(geometry)
        } action: { _, metrics in
            zoom.apply(metrics)
            let nextViewport = CanvasRenderCulling.logicalVisibleRect(metrics.visibleRect, zoom: zoom.zoom)
            if CanvasRenderCulling.shouldUpdateViewport(current: renderViewport, next: nextViewport) {
                renderViewport = nextViewport
            }
            onCanvasGeometryReady(boardID, generation, metrics)
        }
        .onScrollPhaseChange { _, phase in
            guard phase == .idle else { return }
            onCanvasChange(boardID, generation, zoom.confirmedWorkspace())
        }
        .onChange(of: CGSize(width: extent.width, height: extent.height), initial: true) { zoom.contentExtent = $1 }
        .onChange(of: reduceMotion, initial: true) { zoom.reduceMotion = $1 }
        .onChange(of: zoom.scrollRequest, initial: true) { _, request in
            guard let request else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                scrollPosition.scrollTo(point: request.point)
            }
        }
        .onChange(of: zoom.zoom) { _, newZoom in
            // O controlador já publicou o retângulo compensado no mesmo commit do zoom.
            // Preservar o último recorte se ainda não houver geometria evita construir
            // todos os cartões por um quadro enquanto o ScrollView atualiza o layout.
            renderViewport = CanvasRenderCulling.viewportAfterZoom(
                current: renderViewport,
                visibleRect: zoom.visibleRect,
                zoom: newZoom)
        }
        // Limpeza adiada do gesto inativo. Um novo gesto ou a saída da view cancela esta tarefa,
        // para uma limpeza antiga não apagar o deslocamento ou tamanho do gesto seguinte.
        .task(id: isDragging) {
            guard !isDragging else { return }
            // Um gesto de texto livre também pode ser cancelado sem `onEnded`.
            // Limpar o deslocamento transitório evita deixar a anotação desenhada
            // numa posição que nunca foi persistida.
            await Task.yield()
            guard !Task.isCancelled, !isDragging else { return }
            freeTextDrag = nil
            // O tamanho ao vivo também não pode permanecer desenhado sem ter sido gravado.
            resizing = nil
            // Um cartão sendo guardado ainda precisa do arrasto até o fim da animação.
            guard drag != nil, storing == nil else { return }
            drag = nil
            hoveredFolder = pointerFolder
        }
        .gesture(
            MagnifyGesture()
                .onChanged { zoom.pinchChanged(magnification: $0.magnification, startLocation: $0.startLocation) }
                .onEnded { zoom.pinchEnded(magnification: $0.magnification) }
        )
        .overlay(alignment: .bottomTrailing) {
            CanvasControls(zoom: zoom)
                .nowPlayingObstacle()
                .padding(18)
        }
        // O menu Visualizar só age no mural quando ele está na frente.
        .focusedSceneValue(hero.presented.isEmpty ? zoom : nil)
        .onChange(of: isMarqueeActive) { _, active in
            if active { hoveredFolder = nil }
        }
        .onChange(of: liveDrag) { _, drag in liveShare?.dragChanged(drag, in: boardID) }
        // Libera a pasta depois de `armingDelay` com o ponteiro em cima dela; o toque marca o momento.
        .task(id: drag?.tracker?.candidate) { await armCandidateFolder() }
        .onChange(of: drag?.tracker?.target) { _, new in
            if new != nil { HapticFeedback.play() }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: hoveredFolder)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: filter)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: colorFilter)
    }

    // MARK: Cartões

    @ViewBuilder
    private func cardGroup(
        for item: BoardItem, size cachedSize: BoardSize? = nil, focus: BoardFocus
    ) -> some View {
        let size = cachedSize ?? displayedSize(of: item)
        if item.kind == .folder {
            // O leque da pasta sai pela borda direita: a prévia começa depois dele, com a folga de 14 pt de sempre.
            HStack(alignment: .top, spacing: FolderCard.fanReach + 14) {
                cardButton(item, open: [.collection(item.id)], size: size)
                    .frame(width: size.width, height: size.height)
                    .dropTargetHighlight(highlightState(of: item, focus: focus))
                    .highPriorityGesture(moveGesture(for: item))
                // Nunca junto com a pasta aberta: os dois desenhariam os mesmos cartões
                // com o mesmo id de transição, e o SwiftUI não saberia qual é a origem.
                if hoveredFolder == item.id && !hero.presented.contains(item.id) {
                    FolderPeek(folder: item, model: model, hero: hero) { child in
                        // Subpasta abre como outro nível de pasta; o resto, como página de item.
                        let isFolder = model.item(id: child)?.kind == .folder
                        open([.collection(item.id), isFolder ? .collection(child) : .item(child)])
                    }
                    // A prévia sai de dentro da pasta: cresce a partir da borda dela enquanto
                    // uma borda suave (Metal) revela os cartões da esquerda para a direita.
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: AnyTransition(PeekReveal()).combined(with: .scale(scale: 0.85, anchor: .leading)),
                                removal: .opacity
                            )
                    )
                }
            }
            .onHover { inside in pointerMoved(over: item.id, inside: inside) }
        } else if BoardLayout.isResizable(item.kind) {
            cardButton(item, open: [.item(item.id)], size: size)
                .frame(width: size.width, height: size.height)
                // A letra e a margem do post-it acompanham o tamanho mostrado, inclusive durante o arrasto do canto.
                .contentScaled(for: item, width: size.width, height: size.height)
                // A alça vem antes do gesto: o arrasto que começa nela chega ao gesto do cartão, que decide pelo canto.
                .resizeHandle(isVisible: showsResizeHandle(for: .item(item.id)), zoom: zoom.zoom)
                .resizeCornerPointer(size: size, zoom: zoom.zoom, isEnabled: allowsResizeCornerPointer)
                .resizeProportionFeedback(
                    resizing?.target == .item(item.id) ? resizing?.proportion : nil, corner: resizing?.corner ?? .bottomTrailing,
                    zoom: zoom.zoom
                )
                .onHover { inside in resizableHoverChanged(.item(item.id), inside: inside) }
                .highPriorityGesture(moveGesture(for: item))
        } else {
            cardButton(item, open: [.item(item.id)], size: size)
                .frame(width: size.width, height: size.height)
                .highPriorityGesture(moveGesture(for: item))
        }
    }

    private func cardButton(
        _ item: BoardItem,
        open destinations: [Destination],
        size: BoardSize? = nil
    ) -> some View {
        CardButton(
            item: item,
            model: model,
            hero: hero,
            onOpen: { open(destinations) },
            onDelete: onDelete,
            onMoveToBoard: onMoveToBoard,
            onMoveIntoFolder: onMoveIntoFolder,
            onSetColorTag: onSetColorTag,
            onRename: onRename,
            onEditCaption: onEditCaption,
            onResize: { id, size in commitResize(.item(id), to: size) },
            isStandardSize: size.map { displayedSize in
                let standard = BoardLayout.cardSize(for: item.kind)
                return displayedSize.width == standard.width && displayedSize.height == standard.height
            },
            onToggleReminder: onToggleReminder,
            onToggleMusic: onToggleMusic,
            musicPhase: item.kind == .music ? musicPhase?(item.id) ?? .idle : .idle,
            selection: selection)
    }

    /// Tamanho do cartão na tela: o do arrasto do canto em andamento ou, fora dele, o do domínio (`BoardLayout.size(of:)`).
    private func displayedSize(of item: BoardItem) -> BoardSize {
        if let resizing, resizing.target == .item(item.id) { return resizing.size }
        let size = BoardLayout.size(of: item)
        return BoardSize(width: size.width, height: size.height)
    }

    /// O mesmo de `displayedSize(of:)` para um texto livre.
    private func displayedSize(of freeText: BoardFreeText) -> BoardSize {
        if let resizing, resizing.target == .freeText(freeText.id) { return resizing.size }
        let size = BoardLayout.size(of: freeText)
        return BoardSize(width: size.width, height: size.height)
    }

    private func displayedSizes(for items: [BoardItem], when viewport: CGRect) -> [UUID: BoardSize] {
        guard !viewport.isEmpty else { return [:] }
        return model.rootItemSizes
    }

    private func displayedSizes(for freeTexts: [BoardFreeText], when viewport: CGRect) -> [UUID: BoardSize] {
        guard !viewport.isEmpty else { return [:] }
        return model.freeTextSizes
    }

    private enum DisplayedSizeKind {
        case item
        case freeText
    }

    private func displayedSizeOverride(
        for kind: DisplayedSizeKind, when viewport: CGRect
    ) -> CanvasRenderCulling.SizeOverride? {
        guard !viewport.isEmpty, let resizing else { return nil }
        switch (kind, resizing.target) {
        case (.item, .item(let id)), (.freeText, .freeText(let id)):
            return CanvasRenderCulling.SizeOverride(id: id, size: resizing.size)
        default:
            return nil
        }
    }

    private func displayedSize(
        for item: BoardItem, cachedSizes: [UUID: BoardSize], override: CanvasRenderCulling.SizeOverride?
    ) -> BoardSize {
        if override?.id == item.id, let size = override?.size { return size }
        return cachedSizes[item.id] ?? displayedSize(of: item)
    }

    private func displayedSize(
        for freeText: BoardFreeText, cachedSizes: [UUID: BoardSize], override: CanvasRenderCulling.SizeOverride?
    ) -> BoardSize {
        if override?.id == freeText.id, let size = override?.size { return size }
        return cachedSizes[freeText.id] ?? displayedSize(of: freeText)
    }

    /// Posição do cartão: a gravada mais o arrasto em andamento, ou a do redimensionamento por um canto de cima ou da esquerda.
    private func offset(for item: BoardItem) -> CGSize {
        if let resizing, resizing.target == .item(item.id) {
            return CGSize(width: resizing.origin.x, height: resizing.origin.y)
        }
        let moved = (drag?.id == item.id || drag?.origins[item.id] != nil) ? drag?.translation ?? .zero : .zero
        return CGSize(width: item.position.x + moved.width, height: item.position.y + moved.height)
    }

    private func freeTextOffset(for freeText: BoardFreeText) -> CGSize {
        if let resizing, resizing.target == .freeText(freeText.id) {
            return CGSize(width: resizing.origin.x, height: resizing.origin.y)
        }
        let moved = freeTextDrag?.id == freeText.id ? freeTextDrag?.translation ?? .zero : .zero
        return CGSize(width: freeText.position.x + moved.width, height: freeText.position.y + moved.height)
    }

    /// Ponto para onde o cartão encolhe ao ser guardado: o centro da pasta de destino, medido no
    /// quadro do próprio cartão (por isso pode cair fora de 0...1).
    private func storeAnchor(for item: BoardItem, size cachedSize: BoardSize? = nil) -> UnitPoint {
        guard let drag, drag.id == item.id, let target = drag.tracker?.target, let folder = model.item(id: target)
        else { return .center }
        let size = cachedSize ?? displayedSize(of: item)
        let folderSize = BoardLayout.cardSize(for: .folder)
        let origin = offset(for: item)
        return UnitPoint(
            x: (folder.position.x + folderSize.width / 2 - origin.width) / size.width,
            y: (folder.position.y + folderSize.height / 2 - origin.height) / size.height)
    }

    /// Encolhimento do cartão arrastado (e dos demais do grupo) enquanto o ponteiro está sobre uma pasta:
    /// se deve estar encolhido, o ponteiro no quadro do cartão e a escala mínima dele.
    private func hoverShrinkState(for item: BoardItem, size: BoardSize) -> (isShrunk: Bool, anchor: CGPoint, minScale: CGFloat) {
        let isDragged = drag?.id == item.id || drag?.origins[item.id] != nil
        let pointer = drag?.pointer ?? .zero
        let origin = offset(for: item)
        return (
            isDragged && drag?.tracker?.candidate != nil,
            CGPoint(x: pointer.x - origin.width, y: pointer.y - origin.height),
            FolderHoverShrink.minScale(for: CGSize(width: size.width, height: size.height))
        )
    }

    /// Destaque da pasta: leve enquanto espera o tempo de liberar, completo quando liberada.
    private func highlightState(of item: BoardItem, focus: BoardFocus) -> DropHighlightState {
        guard focus.dropTarget == item.id else { return .none }
        return focus.dropArmed ? .armed : .pending
    }

    /// Espera `armingDelay` com a mesma pasta candidata sob o ponteiro e então a libera. Trocar de pasta
    /// ou sair dela cancela a tarefa (o `id` muda) e a espera recomeça.
    private func armCandidateFolder() async {
        guard let candidate = drag?.tracker?.candidate else { return }
        try? await Task.sleep(for: .seconds(FolderDropTracker.armingDelay))
        guard !Task.isCancelled, drag?.tracker?.candidate == candidate else { return }
        drag?.tracker?.arm()
    }

    /// Abre um nível e desliga o destaque de pasta: a prévia sai na mesma animação em que
    /// a pasta entra, e os cartões dela viajam da prévia para a grade.
    private func open(_ destinations: [Destination]) {
        hoveredFolder = nil
        pointerFolder = nil
        onOpen(destinations)
    }

    /// Ponto em coordenadas do conteúdo convertido para a âncora relativa de `scaleEffect`.
    private func unitPoint(_ point: CGPoint, in size: CGSize) -> UnitPoint {
        guard size.width > 0, size.height > 0 else { return .topLeading }
        return UnitPoint(x: point.x / size.width, y: point.y / size.height)
    }

    // MARK: Arrastar

    /// Arrasto de um cartão solto. O clique simples continua abrindo: o gesto só começa depois
    /// de 4 pontos de movimento e, por ter prioridade sobre o botão, impede que o arrasto abra o cartão.
    /// Soltar sobre uma pasta guarda o cartão nela; pastas também podem ser guardadas, mas só nas
    /// que o domínio aceita (não nela mesma, nas de dentro dela nem além do último nível).
    ///
    /// Num post-it ou numa foto, o arrasto que começa no quadrado de um dos quatro cantos muda o tamanho em vez do lugar, e o canto
    /// oposto fica parado. É este gesto que decide, pelo ponto onde o arrasto começou: um segundo gesto no canto perderia para
    /// este, que tem prioridade.
    private func moveGesture(for item: BoardItem) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .updating($isDragging) { _, isDragging, _ in isDragging = true }
            .onChanged { value in
                if let corner = resizeCorner(of: item, at: value.startLocation) {
                    updateResize(.item(item.id), corner: corner, with: value)
                    return
                }
                // Outro cartão ainda está entrando numa pasta: espera a animação terminar.
                guard storing == nil else { return }
                // No começo do arrasto, anota a pasta que já estava sob o ponteiro.
                var current: CardDrag
                if let existing = drag, existing.id == item.id {
                    current = existing
                } else {
                    let selected = selection?.selected ?? []
                    let group =
                        selected.contains(item.id) && selected.count > 1
                        ? model.rootItems.filter { selected.contains($0.id) } : []
                    let origins =
                        group.count > 1
                        ? Dictionary(uniqueKeysWithValues: group.map { ($0.id, $0.position) }) : [:]
                    let movingIDs = origins.isEmpty ? [item.id] : Array(origins.keys)
                    let accepted = movingIDs.dropFirst().reduce(Set(model.folderDestinations(for: movingIDs[0]).map(\.id))) {
                        $0.intersection(model.folderDestinations(for: $1).map(\.id))
                    }.subtracting(movingIDs)
                    let acceptedRootItems = model.rootItems.filter { accepted.contains($0.id) }
                    current = CardDrag(
                        id: item.id, translation: .zero,
                        origins: origins,
                        tracker: FolderDropTracker(
                            startFolder: folderID(
                                at: value.startLocation,
                                among: acceptedRootItems,
                                excluding: item.id)),
                        acceptedRootItems: acceptedRootItems)
                }
                current.translation = current.groupTranslation(value.translation)
                current.pointer = value.location
                current.tracker?.update(
                    folderUnderPointer: folderID(
                        at: value.location,
                        among: current.acceptedRootItems,
                        excluding: item.id))
                if !current.origins.isEmpty { hoveredFolder = nil }
                drag = current
            }
            .onEnded { value in
                if let corner = resizeCorner(of: item, at: value.startLocation) {
                    endResize(.item(item.id), corner: corner, with: value)
                    return
                }
                guard storing == nil, var final = drag, final.id == item.id else { return }
                if !final.origins.isEmpty {
                    final.tracker?.update(
                        folderUnderPointer: folderID(
                            at: value.location, among: final.acceptedRootItems, excluding: item.id))
                    if let destination = final.tracker?.target {
                        if let onMoveGroupIntoFolder {
                            onMoveGroupIntoFolder(final.origins, destination)
                        } else {
                            _ = model.moveGroupIntoFolder(final.origins, folderID: destination)
                        }
                        drag = nil
                        onCanvasChange(boardID, generation, zoom.confirmedWorkspace())
                        hoveredFolder = pointerFolder
                        return
                    }
                    let translation = final.groupTranslation(value.translation)
                    let positions = final.origins.mapValues {
                        BoardPoint(x: $0.x + translation.width, y: $0.y + translation.height)
                    }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        if let onMoveGroup {
                            onMoveGroup(final.origins, positions)
                        } else if final.origins.allSatisfy({ model.item(id: $0.key)?.position == $0.value }) {
                            model.arrange(positions)
                        }
                        drag = nil
                    }
                    onCanvasChange(boardID, generation, zoom.confirmedWorkspace())
                    hoveredFolder = pointerFolder
                    return
                }
                // Decide pelo ponto em que o botão foi solto: num arrasto rápido ele pode não ter
                // chegado num `onChanged`, e o destino anotado estaria atrasado.
                final.translation = value.translation
                final.tracker?.update(
                    folderUnderPointer: folderID(
                        at: value.location,
                        among: final.acceptedRootItems,
                        excluding: item.id))
                if let folderID = final.tracker?.target {
                    drag = final
                    store(item, in: folderID)
                    return
                }
                let target = BoardPoint(
                    x: item.position.x + value.translation.width, y: item.position.y + value.translation.height)
                // Sem animação: o cartão já está onde o ponteiro o deixou.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    if let onMove { onMove(item.id, target) } else { model.move(item.id, to: target) }
                    drag = nil
                }
                onCanvasChange(boardID, generation, zoom.confirmedWorkspace())
                hoveredFolder = pointerFolder
            }
    }

    /// Arrasto de um texto livre. Como no post-it, o arrasto que começa no quadrado de um dos quatro cantos muda o tamanho em vez
    /// do lugar.
    private func freeTextMoveGesture(for freeText: BoardFreeText) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .updating($isDragging) { _, isDragging, _ in isDragging = true }
            .onChanged { value in
                if let corner = resizeCorner(of: freeText, at: value.startLocation) {
                    updateResize(.freeText(freeText.id), corner: corner, with: value)
                    return
                }
                freeTextDrag = FreeTextDrag(id: freeText.id, translation: value.translation)
            }
            .onEnded { value in
                if let corner = resizeCorner(of: freeText, at: value.startLocation) {
                    endResize(.freeText(freeText.id), corner: corner, with: value)
                    return
                }
                let target = BoardPoint(
                    x: freeText.position.x + value.translation.width,
                    y: freeText.position.y + value.translation.height
                )
                if let onFreeTextMove {
                    onFreeTextMove(freeText.id, target)
                } else {
                    model.moveFreeText(freeText.id, to: target)
                }
                freeTextDrag = nil
                onCanvasChange(boardID, generation, zoom.confirmedWorkspace())
            }
    }

    // MARK: Redimensionar

    /// O canto de um post-it ou de uma foto que um arrasto começado em `point` (em pontos do mural) pegou, ou `nil` se ele só move.
    /// Com o seletor de ⌘ aberto não há canto, e o arrasto volta a mover.
    private func resizeCorner(of item: BoardItem, at point: CGPoint) -> ResizeCorner? {
        guard BoardLayout.isResizable(item.kind), selection?.isActive != true else { return nil }
        return resizeCorner(at: point, origin: item.position, size: BoardLayout.size(of: item))
    }

    /// O mesmo de `resizeCorner(of:at:)` para um texto livre.
    private func resizeCorner(of freeText: BoardFreeText, at point: CGPoint) -> ResizeCorner? {
        guard selection?.isActive != true else { return nil }
        return resizeCorner(at: point, origin: freeText.position, size: BoardLayout.size(of: freeText))
    }

    /// O quadrado de cada canto tem 18 pontos de tela, ou seja `18 / zoom` pontos do mural, como o da alça (`ResizeCornerHit`).
    /// Num elemento que fica pequeno na tela só existe o canto de baixo à direita, para sobrar onde pegar e mover. O ponto de
    /// partida é medido no tamanho gravado: o arrasto ainda não tinha mudado nada.
    private func resizeCorner(at point: CGPoint, origin: BoardPoint, size: (width: Double, height: Double)) -> ResizeCorner? {
        ResizeCornerHit.corner(
            at: CGPoint(x: point.x - origin.x, y: point.y - origin.y),
            size: CGSize(width: size.width, height: size.height), zoom: zoom.zoom)
    }

    /// O quadro (posição e tamanho) que o arrasto do canto dá ao elemento, a partir do quadro gravado. A mesma conta vale enquanto
    /// o ponteiro se move e ao soltar, quando o estado ao vivo pode já ter sido limpo. Numa foto, o tamanho encaixa nas proporções
    /// da lista quando passa perto delas, e a proporção do encaixe vem junto. `nil` se o elemento deixou de existir.
    private func resizedFrame(
        for target: ResizeDrag.Target, corner: ResizeCorner, translation: CGSize, keepingProportion: Bool
    ) -> (origin: BoardPoint, size: BoardSize, proportion: ImageProportion?)? {
        switch target {
        case .item(let id):
            guard let item = model.item(id: id) else { return nil }
            return BoardLayout.resizedFrame(
                of: item, corner: corner, deltaWidth: translation.width, deltaHeight: translation.height,
                keepingProportion: keepingProportion)
        case .freeText(let id):
            guard let freeText = model.freeText(id: id) else { return nil }
            let frame = BoardLayout.resizedFrame(
                of: freeText, corner: corner, deltaWidth: translation.width, deltaHeight: translation.height,
                keepingProportion: keepingProportion)
            return (frame.origin, frame.size, nil)
        }
    }

    /// Atualiza o quadro ao vivo. Com Shift, mantém a proporção do tamanho de partida.
    private func updateResize(_ target: ResizeDrag.Target, corner: ResizeCorner, with value: DragGesture.Value) {
        let keepsProportion = NSEvent.modifierFlags.contains(.shift)
        guard
            let frame = resizedFrame(
                for: target, corner: corner, translation: value.translation, keepingProportion: keepsProportion)
        else { return }
        resizing = ResizeDrag(
            target: target, corner: corner, origin: frame.origin, size: frame.size, keepsProportion: keepsProportion,
            proportion: frame.proportion)
    }

    /// Grava o quadro em que o arrasto terminou, sem animação: o elemento já está onde o ponteiro o deixou. Recalcula pelo ponto
    /// onde o botão foi solto, e não pelo último quadro ao vivo, que num arrasto rápido pode estar atrasado. A proporção é a do
    /// último movimento, para o valor gravado ser o que a pessoa via.
    private func endResize(_ target: ResizeDrag.Target, corner: ResizeCorner, with value: DragGesture.Value) {
        let keepsProportion = resizing?.target == target ? resizing?.keepsProportion : nil
        let frame = resizedFrame(
            for: target, corner: corner, translation: value.translation,
            keepingProportion: keepsProportion ?? NSEvent.modifierFlags.contains(.shift))
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let frame { commitResize(target, to: frame.size, at: corner == .bottomTrailing ? nil : frame.origin) }
            resizing = nil
        }
        onCanvasChange(boardID, generation, zoom.confirmedWorkspace())
    }

    /// Entrega o tamanho a quem grava: a sessão, ou direto o modelo quando o mural roda sem sessão. `nil` volta ao padrão. Com
    /// `origin`, grava também a posição numa só alteração (cantos da esquerda e de cima); sem ela, a posição não muda, como nos
    /// menus de tamanho, que mantêm o canto de cima, à esquerda, parado.
    private func commitResize(_ target: ResizeDrag.Target, to size: BoardSize?, at origin: BoardPoint? = nil) {
        switch (target, origin) {
        case (.item(let id), nil):
            if let onResize { onResize(id, size) } else { _ = model.resize(id, to: size) }
        case (.item(let id), .some(let origin)):
            if let onResizeFrame { onResizeFrame(id, size, origin) } else { _ = model.resize(id, to: size, at: origin) }
        case (.freeText(let id), nil):
            if let onFreeTextResize { onFreeTextResize(id, size) } else { _ = model.resizeFreeText(id, to: size) }
        case (.freeText(let id), .some(let origin)):
            if let onFreeTextResizeFrame {
                onFreeTextResizeFrame(id, size, origin)
            } else {
                _ = model.resizeFreeText(id, to: size, at: origin)
            }
        }
    }

    /// O cursor de redimensionar dos cantos só aparece quando nada é movido, sem o seletor de ⌘ e sem o retângulo de Shift.
    private var allowsResizeCornerPointer: Bool {
        selection?.isActive != true && drag == nil && freeTextDrag == nil && !isMarqueeActive
    }

    /// A alça aparece com o ponteiro sobre o elemento ou durante o arrasto do canto; some com o seletor de ⌘ aberto e enquanto
    /// qualquer elemento está sendo movido ou o retângulo de Shift está aberto.
    private func showsResizeHandle(for target: ResizeDrag.Target) -> Bool {
        guard selection?.isActive != true else { return false }
        if resizing?.target == target { return true }
        return hoveredResizable == target && resizing == nil && drag == nil && freeTextDrag == nil && !isMarqueeActive
    }

    private func resizableHoverChanged(_ target: ResizeDrag.Target, inside: Bool) {
        if inside {
            hoveredResizable = target
        } else if hoveredResizable == target {
            hoveredResizable = nil
        }
    }

    /// Aceita o drop no domínio imediatamente. A animação de armazenamento não
    /// pode atrasar a mudança de parentID nem a persistência da sessão.
    private func store(_ item: BoardItem, in folderID: UUID) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let onMoveIntoFolder { onMoveIntoFolder(item.id, folderID) } else { model.moveIntoFolder(item.id, folderID: folderID) }
            drag = nil
            storing = nil
        }
        onCanvasChange(boardID, generation, zoom.confirmedWorkspace())
        hoveredFolder = pointerFolder
    }

    /// Pasta solta sob um ponto do mural, sem contar o cartão arrastado e só entre as que o
    /// domínio aceita como destino: o soltar nunca é recusado em silêncio.
    private func folderID(at point: CGPoint, among candidates: [BoardItem], excluding id: UUID) -> UUID? {
        BoardLayout.folderID(at: BoardPoint(x: point.x, y: point.y), among: candidates, excluding: id)
    }

    /// Atualiza a pasta sob o ponteiro; fora de um arrasto, ela vira o foco na hora.
    private func pointerMoved(over folderID: UUID, inside: Bool) {
        pointerFolder = inside ? folderID : (pointerFolder == folderID ? nil : pointerFolder)
        if drag == nil && !isDragging && !isMarqueeActive { hoveredFolder = pointerFolder }
    }

    /// Quadro de cada cartão solto, em pontos do mural, no tamanho mostrado; a pasta conta só o cartão, sem o leque.
    private func cardFrames(
        of items: [BoardItem], displayedSizes: [UUID: BoardSize] = [:], sizeOverride: CanvasRenderCulling.SizeOverride? = nil
    ) -> [UUID: CGRect] {
        var frames: [UUID: CGRect] = [:]
        frames.reserveCapacity(items.count)
        for item in items {
            let size = displayedSize(for: item, cachedSizes: displayedSizes, override: sizeOverride)
            frames[item.id] = CGRect(x: item.position.x, y: item.position.y, width: size.width, height: size.height)
        }
        return frames
    }
}

/// Cartão em arrasto e quanto já andou desde que o gesto começou, em pontos do mural.
private struct CardDrag {
    var id: UUID
    var translation: CGSize
    /// Ponteiro em pontos do mural; é para onde os cartões encolhem sobre uma pasta.
    var pointer = CGPoint.zero
    var origins: [UUID: BoardPoint]
    /// Acompanha a pasta que receberia o cartão (pastas também podem ser guardadas).
    var tracker: FolderDropTracker?
    /// Pastas soltas já filtradas para não reconstruir a lista a cada evento de ponteiro.
    var acceptedRootItems: [BoardItem]

    func groupTranslation(_ translation: CGSize) -> CGSize {
        guard !origins.isEmpty else { return translation }
        let minX = origins.values.map(\.x).min() ?? 0
        let minY = origins.values.map(\.y).min() ?? 0
        return CGSize(width: max(-minX, translation.width.rounded()), height: max(-minY, translation.height.rounded()))
    }
}

private struct FreeTextDrag: Equatable {
    var id: UUID
    var translation: CGSize
}

// MARK: Live Share

extension BoardCanvasView {
    /// O elemento que esta pessoa arrasta agora, para as outras verem: o cartão (ou, senão, o texto livre) e o canto superior esquerdo
    /// de onde ele está, em pontos do mural. `nil` sem arrasto.
    fileprivate var liveDrag: LiveDrag? {
        if let drag, let item = model.item(id: drag.id) {
            return LiveDrag(
                kind: .item, id: item.id, x: item.position.x + drag.translation.width, y: item.position.y + drag.translation.height)
        }
        if let freeTextDrag, let freeText = model.freeText(id: freeTextDrag.id) {
            return LiveDrag(
                kind: .freeText, id: freeText.id, x: freeText.position.x + freeTextDrag.translation.width,
                y: freeText.position.y + freeTextDrag.translation.height)
        }
        return nil
    }
}
