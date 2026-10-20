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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Folga em volta dos cartões, para o mural não terminar colado no último.
    private static let margin: CGFloat = 240

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
                        .cardEmphasis(emphasis(for: item))
                        .offset(x: item.position.x, y: item.position.y)
                        .zIndex(layer(for: item))
                }
            }
            .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
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
            .onHover { inside in
                hoveredFolder = inside ? item.id : (hoveredFolder == item.id ? nil : hoveredFolder)
            }
        } else {
            cardButton(item, open: [.item(item.id)])
                .frame(width: size.width, height: size.height)
        }
    }

    private func cardButton(_ item: BoardItem, open destinations: [Destination]) -> some View {
        CardButton(item: item, model: model, hero: hero) { open(destinations) }
    }

    /// Abre um nível e desliga o destaque de pasta: a prévia sai na mesma animação em que
    /// a pasta entra, e os cartões dela viajam da prévia para a grade.
    private func open(_ destinations: [Destination]) {
        hoveredFolder = nil
        onOpen(destinations)
    }

    /// Esmaece o que não é foco: o resto do mural quando uma pasta está em destaque,
    /// ou o que não combina com o filtro escolhido.
    private func emphasis(for item: BoardItem) -> Double {
        if let hoveredFolder, hoveredFolder != item.id { return 0.3 }
        return filter?.emphasis(for: item.kind) ?? 1
    }

    /// Empilhamento: a pasta em foco fica por cima de tudo e, com um filtro, os cartões
    /// destacados passam à frente dos esmaecidos. Como o esmaecido continua sólido, um
    /// cartão apagado por cima esconderia parte do destacado.
    private func layer(for item: BoardItem) -> Double {
        if item.id == hoveredFolder { return 2 }
        return emphasis(for: item) < 1 ? 0 : 1
    }

    /// Ponto em coordenadas do conteúdo convertido para a âncora relativa de `scaleEffect`.
    private func unitPoint(_ point: CGPoint, in size: CGSize) -> UnitPoint {
        guard size.width > 0, size.height > 0 else { return .topLeading }
        return UnitPoint(x: point.x / size.width, y: point.y / size.height)
    }
}
