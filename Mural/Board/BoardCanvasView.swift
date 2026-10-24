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
    /// Grava o tamanho de um post-it, arrastando o canto ou pelo menu (`nil` volta ao padrão). `nil` fala direto com o modelo,
    /// como `onMove`.
    var onResize: ((UUID, BoardSize?) -> Void)? = nil
    var onFreeTextEdit: ((UUID) -> Void)? = nil
    var onFreeTextMove: ((UUID, BoardPoint) -> Void)? = nil
    /// O mesmo de `onResize` para um texto livre.
    var onFreeTextResize: ((UUID, BoardSize?) -> Void)? = nil
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
    /// Post-it ou texto livre com o ponteiro em cima: é quando a alça de redimensionar aparece.
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
    /// Volta sozinho a falso, inclusive quando o gesto é cancelado sem `onEnded`.
    @GestureState private var isDragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Folga em volta dos cartões, para o mural não terminar colado no último.
    private static let margin: CGFloat = 240
    /// Nome do espaço de coordenadas em que os arrastos são medidos.
    private static let space = "mural"

    /// O que está em destaque agora: pasta em foco, cartão arrastado, pasta de destino e filtro.
    private var focus: BoardFocus {
        BoardFocus(
            hoveredFolder: hoveredFolder, dragged: drag?.id, dropTarget: drag?.tracker?.target, filter: filter,
            colorFilter: colorFilter)
    }

    var body: some View {
        let items = model.rootItems
        let freeTexts = model.freeTexts
        let extent = BoardLayout.extent(of: items, freeTexts: freeTexts)
        let viewport = zoom.viewport
        // Como num quadro branco: sempre uma tela de folga à direita e embaixo, para o
        // zoom poder manter parado o ponto sob os dedos (ou o centro da janela).
        let slack = CGSize(width: viewport.width / zoom.zoom, height: viewport.height / zoom.zoom)
        let contentSize = CGSize(
            width: max(extent.width + Self.margin, slack.width) + slack.width,
            height: max(extent.height + Self.margin, slack.height) + slack.height
        )
        let layoutSize = CGSize(width: contentSize.width * zoom.zoom, height: contentSize.height * zoom.zoom)

        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                ForEach(items) { item in
                    cardGroup(for: item)
                        .cardEmphasis(focus.emphasis(for: item))
                        // Guardado numa pasta: encolhe em direção a ela e some antes de sair do mural.
                        .scaleEffect(storing == item.id ? 0.1 : 1, anchor: storeAnchor(for: item))
                        .opacity(storing == item.id ? 0 : 1)
                        .offset(offset(for: item))
                        .zIndex(focus.layer(for: item))
                }
                ForEach(freeTexts) { freeText in
                    BoardFreeTextView(
                        freeText: freeText,
                        size: displayedSize(of: freeText),
                        onEdit: { onFreeTextEdit?(freeText.id) },
                        onDelete: { onFreeTextDelete?(freeText.id) },
                        onResize: { size in
                            withAnimation(reduceMotion ? nil : .smooth) { commitResize(.freeText(freeText.id), to: size) }
                        }
                    )
                    // A alça vem antes do gesto: o arrasto que começa nela chega ao gesto do texto, que decide pelo canto.
                    .resizeHandle(isVisible: showsResizeHandle(for: .freeText(freeText.id)), zoom: zoom.zoom)
                    .onHover { inside in resizableHoverChanged(.freeText(freeText.id), inside: inside) }
                    .offset(freeTextOffset(for: freeText))
                    .zIndex(100)
                    .highPriorityGesture(freeTextMoveGesture(for: freeText))
                }
            }
            .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
            // Shift + arrastar no vazio marca os cartões cruzados; o contorno fica com um ponto na tela.
            .marqueeSelecting(
                in: Self.space, selection: selection, lineWidth: 1 / zoom.zoom, isActive: $isMarqueeActive
            ) {
                cardFrames(of: items)
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
        // Gesto cancelado sem `onEnded`: desfaz o arrasto. Fica para a volta seguinte do laço
        // principal, para não atropelar o `onEnded` quando ele vier.
        .onChange(of: isDragging) { _, active in
            guard !active else { return }
            // Um gesto de texto livre também pode ser cancelado sem `onEnded`.
            // Limpar o deslocamento transitório evita deixar a anotação desenhada
            // numa posição que nunca foi persistida.
            freeTextDrag = nil
            Task { @MainActor in
                // O mesmo vale para o redimensionar: o tamanho ao vivo não pode ficar desenhado sem ter sido gravado. Fica para
                // a volta seguinte, como o arrasto abaixo, para não apagar o tamanho na frente do `onEnded` que o grava.
                resizing = nil
                // Um cartão sendo guardado ainda precisa do arrasto até o fim da animação.
                guard drag != nil, storing == nil else { return }
                drag = nil
                hoveredFolder = pointerFolder
            }
        }
        .gesture(
            MagnifyGesture()
                .onChanged { zoom.pinchChanged(magnification: $0.magnification, startLocation: $0.startLocation) }
                .onEnded { zoom.pinchEnded(magnification: $0.magnification) }
        )
        .overlay(alignment: .bottomTrailing) {
            CanvasControls(zoom: zoom)
                .padding(18)
        }
        // O menu Visualizar só age no mural quando ele está na frente.
        .focusedSceneValue(hero.presented.isEmpty ? zoom : nil)
        .onChange(of: isMarqueeActive) { _, active in
            if active { hoveredFolder = nil }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: hoveredFolder)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: filter)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: colorFilter)
    }

    // MARK: Cartões

    @ViewBuilder
    private func cardGroup(for item: BoardItem) -> some View {
        let size = displayedSize(of: item)
        if item.kind == .folder {
            // O leque da pasta sai pela borda direita: a prévia começa depois dele, com a folga de 14 pt de sempre.
            HStack(alignment: .top, spacing: FolderCard.fanReach + 14) {
                cardButton(item, open: [.collection(item.id)])
                    .frame(width: size.width, height: size.height)
                    .dropTargetHighlight(focus.dropTarget == item.id)
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
            cardButton(item, open: [.item(item.id)])
                .frame(width: size.width, height: size.height)
                // A letra e a margem do post-it acompanham o tamanho mostrado, inclusive durante o arrasto do canto.
                .contentScaled(for: item, width: size.width, height: size.height)
                // A alça vem antes do gesto: o arrasto que começa nela chega ao gesto do cartão, que decide pelo canto.
                .resizeHandle(isVisible: showsResizeHandle(for: .item(item.id)), zoom: zoom.zoom)
                .onHover { inside in resizableHoverChanged(.item(item.id), inside: inside) }
                .highPriorityGesture(moveGesture(for: item))
        } else {
            cardButton(item, open: [.item(item.id)])
                .frame(width: size.width, height: size.height)
                .highPriorityGesture(moveGesture(for: item))
        }
    }

    private func cardButton(_ item: BoardItem, open destinations: [Destination]) -> some View {
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
            onToggleReminder: onToggleReminder,
            onToggleMusic: onToggleMusic,
            musicPhase: musicPhase?(item.id) ?? .idle,
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

    /// Posição do cartão: a gravada mais o arrasto em andamento.
    private func offset(for item: BoardItem) -> CGSize {
        let moved = drag?.id == item.id ? drag?.translation ?? .zero : .zero
        return CGSize(width: item.position.x + moved.width, height: item.position.y + moved.height)
    }

    private func freeTextOffset(for freeText: BoardFreeText) -> CGSize {
        let moved = freeTextDrag?.id == freeText.id ? freeTextDrag?.translation ?? .zero : .zero
        return CGSize(width: freeText.position.x + moved.width, height: freeText.position.y + moved.height)
    }

    /// Ponto para onde o cartão encolhe ao ser guardado: o centro da pasta de destino, medido no
    /// quadro do próprio cartão (por isso pode cair fora de 0...1).
    private func storeAnchor(for item: BoardItem) -> UnitPoint {
        guard let drag, drag.id == item.id, let target = drag.tracker?.target, let folder = model.item(id: target)
        else { return .center }
        let size = displayedSize(of: item)
        let folderSize = BoardLayout.cardSize(for: .folder)
        let origin = offset(for: item)
        return UnitPoint(
            x: (folder.position.x + folderSize.width / 2 - origin.width) / size.width,
            y: (folder.position.y + folderSize.height / 2 - origin.height) / size.height)
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
    /// Num post-it, o arrasto que começa no quadrado do canto inferior direito (a alça) muda o tamanho em vez do lugar. É este
    /// gesto que decide, pelo ponto onde o arrasto começou: um segundo gesto no canto perderia para este, que tem prioridade.
    private func moveGesture(for item: BoardItem) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .updating($isDragging) { _, isDragging, _ in isDragging = true }
            .onChanged { value in
                if startsResize(of: item, at: value.startLocation) {
                    updateResize(.item(item.id), with: value)
                    return
                }
                // Outro cartão ainda está entrando numa pasta: espera a animação terminar.
                guard storing == nil else { return }
                // No começo do arrasto, anota a pasta que já estava sob o ponteiro.
                var current: CardDrag
                if let existing = drag, existing.id == item.id {
                    current = existing
                } else {
                    let accepted = Set(model.board.folderDestinations(for: item.id).map(\.id))
                    current = CardDrag(
                        id: item.id, translation: .zero,
                        tracker: FolderDropTracker(
                            startFolder: folderID(at: value.startLocation, excluding: item.id, accepting: accepted)),
                        acceptedFolders: accepted)
                }
                current.translation = value.translation
                current.tracker?.update(
                    folderUnderPointer: folderID(at: value.location, excluding: item.id, accepting: current.acceptedFolders))
                drag = current
            }
            .onEnded { value in
                if startsResize(of: item, at: value.startLocation) {
                    endResize(.item(item.id), with: value)
                    return
                }
                guard storing == nil, var final = drag, final.id == item.id else { return }
                // Decide pelo ponto em que o botão foi solto: num arrasto rápido ele pode não ter
                // chegado num `onChanged`, e o destino anotado estaria atrasado.
                final.translation = value.translation
                final.tracker?.update(
                    folderUnderPointer: folderID(at: value.location, excluding: item.id, accepting: final.acceptedFolders))
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

    /// Arrasto de um texto livre. Como no post-it, o arrasto que começa no quadrado do canto inferior direito muda o tamanho em
    /// vez do lugar.
    private func freeTextMoveGesture(for freeText: BoardFreeText) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .updating($isDragging) { _, isDragging, _ in isDragging = true }
            .onChanged { value in
                if startsResize(of: freeText, at: value.startLocation) {
                    updateResize(.freeText(freeText.id), with: value)
                    return
                }
                freeTextDrag = FreeTextDrag(id: freeText.id, translation: value.translation)
            }
            .onEnded { value in
                if startsResize(of: freeText, at: value.startLocation) {
                    endResize(.freeText(freeText.id), with: value)
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

    /// Se um arrasto que começou em `point` (em pontos do mural) pegou a alça de um post-it. Com o seletor de ⌘ aberto a alça não
    /// existe, e o arrasto do canto volta a mover.
    private func startsResize(of item: BoardItem, at point: CGPoint) -> Bool {
        guard BoardLayout.isResizable(item.kind), selection?.isActive != true else { return false }
        return isInResizeCorner(point, origin: item.position, size: BoardLayout.size(of: item))
    }

    /// O mesmo de `startsResize(of:at:)` para um texto livre.
    private func startsResize(of freeText: BoardFreeText, at point: CGPoint) -> Bool {
        guard selection?.isActive != true else { return false }
        return isInResizeCorner(point, origin: freeText.position, size: BoardLayout.size(of: freeText))
    }

    /// O quadrado do canto inferior direito do elemento: 18 pontos de tela, ou seja `18 / zoom` pontos do mural, como o da alça.
    /// Num elemento que fica pequeno na tela (zoom baixo), o quadrado não passa de metade do menor lado, para sobrar onde pegar
    /// e mover. O ponto de partida é medido no tamanho gravado: o arrasto ainda não tinha mudado nada.
    private func isInResizeCorner(_ point: CGPoint, origin: BoardPoint, size: (width: Double, height: Double)) -> Bool {
        let reach = min(ResizeHandle.cornerSide / zoom.zoom, min(size.width, size.height) / 2)
        let right = origin.x + size.width
        let bottom = origin.y + size.height
        return point.x >= right - reach && point.x <= right && point.y >= bottom - reach && point.y <= bottom
    }

    /// O tamanho que o arrasto do canto dá ao elemento, a partir do tamanho gravado. A mesma conta vale enquanto o ponteiro se
    /// move e ao soltar, quando o estado ao vivo pode já ter sido limpo. `nil` se o elemento deixou de existir.
    private func resizedSize(for target: ResizeDrag.Target, translation: CGSize, keepingProportion: Bool) -> BoardSize? {
        switch target {
        case .item(let id):
            guard let item = model.item(id: id) else { return nil }
            return BoardLayout.resizedSize(
                of: item, deltaWidth: translation.width, deltaHeight: translation.height, keepingProportion: keepingProportion)
        case .freeText(let id):
            guard let freeText = model.freeText(id: id) else { return nil }
            return BoardLayout.resizedSize(
                of: freeText, deltaWidth: translation.width, deltaHeight: translation.height, keepingProportion: keepingProportion)
        }
    }

    /// Atualiza o tamanho ao vivo. Com Shift, mantém a proporção do tamanho de partida.
    private func updateResize(_ target: ResizeDrag.Target, with value: DragGesture.Value) {
        let keepsProportion = NSEvent.modifierFlags.contains(.shift)
        guard let size = resizedSize(for: target, translation: value.translation, keepingProportion: keepsProportion) else { return }
        resizing = ResizeDrag(target: target, size: size, keepsProportion: keepsProportion)
    }

    /// Grava o tamanho em que o arrasto terminou, sem animação: o elemento já está onde o ponteiro o deixou. Recalcula pelo ponto
    /// onde o botão foi solto, e não pelo último tamanho ao vivo, que num arrasto rápido pode estar atrasado. A proporção é a do
    /// último movimento, para o valor gravado ser o que a pessoa via.
    private func endResize(_ target: ResizeDrag.Target, with value: DragGesture.Value) {
        let keepsProportion = resizing?.target == target ? resizing?.keepsProportion : nil
        let size = resizedSize(
            for: target, translation: value.translation, keepingProportion: keepsProportion ?? NSEvent.modifierFlags.contains(.shift))
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let size { commitResize(target, to: size) }
            resizing = nil
        }
        onCanvasChange(boardID, generation, zoom.confirmedWorkspace())
    }

    /// Entrega o tamanho a quem grava: a sessão, ou direto o modelo quando o mural roda sem sessão. `nil` volta ao padrão.
    private func commitResize(_ target: ResizeDrag.Target, to size: BoardSize?) {
        switch target {
        case .item(let id):
            if let onResize { onResize(id, size) } else { _ = model.resize(id, to: size) }
        case .freeText(let id):
            if let onFreeTextResize { onFreeTextResize(id, size) } else { _ = model.resizeFreeText(id, to: size) }
        }
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
    private func folderID(at point: CGPoint, excluding id: UUID, accepting accepted: Set<UUID>) -> UUID? {
        let candidates = model.rootItems.filter { accepted.contains($0.id) }
        return BoardLayout.folderID(at: BoardPoint(x: point.x, y: point.y), among: candidates, excluding: id)
    }

    /// Atualiza a pasta sob o ponteiro; fora de um arrasto, ela vira o foco na hora.
    private func pointerMoved(over folderID: UUID, inside: Bool) {
        pointerFolder = inside ? folderID : (pointerFolder == folderID ? nil : pointerFolder)
        if drag == nil && !isDragging && !isMarqueeActive { hoveredFolder = pointerFolder }
    }

    /// Quadro de cada cartão solto, em pontos do mural, no tamanho mostrado; a pasta conta só o cartão, sem o leque.
    private func cardFrames(of items: [BoardItem]) -> [UUID: CGRect] {
        Dictionary(
            uniqueKeysWithValues: items.map { item in
                let size = displayedSize(of: item)
                return (item.id, CGRect(x: item.position.x, y: item.position.y, width: size.width, height: size.height))
            })
    }
}

/// Cartão em arrasto e quanto já andou desde que o gesto começou, em pontos do mural.
private struct CardDrag: Equatable {
    var id: UUID
    var translation: CGSize
    /// Acompanha a pasta que receberia o cartão (pastas também podem ser guardadas).
    var tracker: FolderDropTracker?
    /// Pastas que o domínio aceita como destino, fixadas no começo do arrasto.
    var acceptedFolders: Set<UUID>
}

private struct FreeTextDrag: Equatable {
    var id: UUID
    var translation: CGSize
}
