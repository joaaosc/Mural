import MuralKit
import SwiftUI

/// Nível 1: o mural livre, com rolagem nos dois sentidos e zoom.
struct BoardCanvasView: View {
    let model: BoardModel
    let hero: HeroContext
    let filter: BoardFilter?
    var onOpen: ([Destination]) -> Void
    var onAdd: () -> Void

    @State private var zoom = CanvasZoomController()
    @State private var hoveredFolder: UUID?
    /// Pasta sob o ponteiro agora, atualizada mesmo durante um arrasto; vira o foco ao soltar.
    @State private var pointerFolder: UUID?
    /// Cartão arrastado e quanto andou, em pontos do mural (sem zoom).
    @State private var drag: CardDrag?
    /// Volta sozinho a falso, inclusive quando o gesto é cancelado sem `onEnded`.
    @GestureState private var isDragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Folga em volta dos cartões, para o mural não terminar colado no último.
    private static let margin: CGFloat = 240
    /// Nome do espaço de coordenadas em que os arrastos são medidos.
    private static let space = "mural"

    /// O que está em destaque agora: pasta em foco, cartão arrastado e filtro.
    private var focus: BoardFocus {
        BoardFocus(hoveredFolder: hoveredFolder, dragged: drag?.id, filter: filter)
    }

    var body: some View {
        let items = model.rootItems
        let extent = BoardLayout.extent(of: items)
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
                        .offset(offset(for: item))
                        .zIndex(focus.layer(for: item))
                }
            }
            .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
            // Os arrastos medem neste espaço, em pontos do mural, sem o zoom.
            .coordinateSpace(.named(Self.space))
            .scaleEffect(zoom.zoom, anchor: .topLeading)
            .frame(width: layoutSize.width, height: layoutSize.height, alignment: .topLeading)
            // Escala visual da pinça, ancorada no ponto entre os dedos.
            .scaleEffect(zoom.liveScale, anchor: unitPoint(zoom.liveAnchor, in: layoutSize))
        }
        .scrollPosition($zoom.scrollPosition)
        .onScrollGeometryChange(for: CGPoint.self, of: \.contentOffset) { _, offset in zoom.scrollOffset = offset }
        .discreetScrollIndicators([.horizontal, .vertical])
        .background(Theme.canvas)
        .onGeometryChange(for: CGSize.self, of: \.size) { zoom.viewport = $0 }
        .onChange(of: CGSize(width: extent.width, height: extent.height), initial: true) { zoom.contentExtent = $1 }
        .onChange(of: reduceMotion, initial: true) { zoom.reduceMotion = $1 }
        // Gesto cancelado sem `onEnded`: desfaz o arrasto. Fica para a volta seguinte do laço
        // principal, para não atropelar o `onEnded` quando ele vier.
        .onChange(of: isDragging) { _, active in
            guard !active else { return }
            Task { @MainActor in
                guard drag != nil else { return }
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
            CanvasControls(zoom: zoom, onAdd: onAdd)
                .padding(18)
        }
        // O menu Visualizar só age no mural quando ele está na frente.
        .focusedSceneValue(hero.presented.isEmpty ? zoom : nil)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: hoveredFolder)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: filter)
    }

    // MARK: Cartões

    @ViewBuilder
    private func cardGroup(for item: BoardItem) -> some View {
        let size = BoardLayout.cardSize(for: item.kind)
        if item.kind == .folder {
            HStack(alignment: .top, spacing: 28) {
                cardButton(item, open: [.collection(item.id)])
                    .frame(width: size.width, height: size.height)
                    .highPriorityGesture(moveGesture(for: item))
                // Nunca junto com a pasta aberta: os dois desenhariam os mesmos cartões
                // com o mesmo id de transição, e o SwiftUI não saberia qual é a origem.
                if hoveredFolder == item.id && !hero.presented.contains(item.id) {
                    FolderPeek(folder: item, model: model, hero: hero) { child in
                        open([.collection(item.id), .item(child)])
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
        CardButton(item: item, model: model, hero: hero) { open(destinations) }
    }

    /// Posição do cartão: a gravada mais o arrasto em andamento.
    private func offset(for item: BoardItem) -> CGSize {
        let moved = drag?.id == item.id ? drag?.translation ?? .zero : .zero
        return CGSize(width: item.position.x + moved.width, height: item.position.y + moved.height)
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
    private func moveGesture(for item: BoardItem) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .updating($isDragging) { _, isDragging, _ in isDragging = true }
            .onChanged { value in drag = CardDrag(id: item.id, translation: value.translation) }
            .onEnded { value in
                let target = BoardPoint(
                    x: item.position.x + value.translation.width, y: item.position.y + value.translation.height)
                // Sem animação: o cartão já está onde o ponteiro o deixou.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    model.move(item.id, to: target)
                    drag = nil
                }
                hoveredFolder = pointerFolder
            }
    }

    /// Atualiza a pasta sob o ponteiro; fora de um arrasto, ela vira o foco na hora.
    private func pointerMoved(over folderID: UUID, inside: Bool) {
        pointerFolder = inside ? folderID : (pointerFolder == folderID ? nil : pointerFolder)
        if drag == nil && !isDragging { hoveredFolder = pointerFolder }
    }
}

/// Cartão em arrasto e quanto já andou desde que o gesto começou, em pontos do mural.
private struct CardDrag: Equatable {
    var id: UUID
    var translation: CGSize
}
