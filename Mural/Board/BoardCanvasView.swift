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
    var onFreeTextEdit: ((UUID) -> Void)? = nil
    var onFreeTextMove: ((UUID, BoardPoint) -> Void)? = nil
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
                        onEdit: { onFreeTextEdit?(freeText.id) },
                        onDelete: { onFreeTextDelete?(freeText.id) }
                    )
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
                Self.cardFrames(of: model.rootItems)
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
        let size = BoardLayout.cardSize(for: item.kind)
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
            onToggleReminder: onToggleReminder,
            onToggleMusic: onToggleMusic,
            musicPhase: musicPhase?(item.id) ?? .idle,
            selection: selection)
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
        let size = BoardLayout.cardSize(for: item.kind)
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
    private func moveGesture(for item: BoardItem) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .updating($isDragging) { _, isDragging, _ in isDragging = true }
            .onChanged { value in
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

    private func freeTextMoveGesture(for freeText: BoardFreeText) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .updating($isDragging) { _, isDragging, _ in isDragging = true }
            .onChanged { value in
                freeTextDrag = FreeTextDrag(id: freeText.id, translation: value.translation)
            }
            .onEnded { value in
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

    /// Quadro de cada cartão solto, em pontos do mural; a pasta conta só o cartão, sem o leque.
    private static func cardFrames(of items: [BoardItem]) -> [UUID: CGRect] {
        Dictionary(
            uniqueKeysWithValues: items.map { item in
                let size = BoardLayout.cardSize(for: item.kind)
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
