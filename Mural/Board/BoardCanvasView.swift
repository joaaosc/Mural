import MuralKit
import SwiftUI

/// Nível 1: o mural livre, com rolagem nos dois sentidos e zoom.
struct BoardCanvasView: View {
    let model: BoardModel
    let hero: HeroContext
    let filter: BoardFilter?
    var onOpen: ([Destination]) -> Void
    var onAdd: () -> Void

    @State private var zoom: CGFloat = 1
    @State private var zoomAtGestureStart: CGFloat = 1
    @State private var viewport: CGSize = .zero
    @State private var hoveredFolder: UUID?
    @State private var scrollPosition = ScrollPosition()

    private static let zoomRange: ClosedRange<CGFloat> = 0.4...2.5
    private static let margin: CGFloat = 240

    /// Tamanho do conteúdo sem zoom: até o último cartão, mais uma margem.
    private var contentSize: CGSize {
        let items = model.rootItems
        let maxX = items.map { $0.position.x + BoardLayout.cardSize(for: $0.kind).width }.max() ?? 0
        let maxY = items.map { $0.position.y + BoardLayout.cardSize(for: $0.kind).height }.max() ?? 0
        return CGSize(
            width: max(maxX + Self.margin, viewport.width / zoom),
            height: max(maxY + Self.margin, viewport.height / zoom)
        )
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                ForEach(model.rootItems) { item in
                    cardGroup(for: item)
                        .offset(x: item.position.x, y: item.position.y)
                        .opacity(opacity(for: item))
                        .zIndex(item.id == hoveredFolder ? 1 : 0)
                }
            }
            .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
            .scaleEffect(zoom, anchor: .topLeading)
            .frame(width: contentSize.width * zoom, height: contentSize.height * zoom, alignment: .topLeading)
        }
        .scrollPosition($scrollPosition)
        .background(Theme.canvas)
        .onGeometryChange(for: CGSize.self, of: \.size) { viewport = $0 }
        .gesture(
            MagnifyGesture()
                .onChanged { value in setZoom(zoomAtGestureStart * value.magnification, animated: false) }
                .onEnded { _ in zoomAtGestureStart = zoom }
        )
        .overlay(alignment: .bottomTrailing) {
            CanvasControls(
                zoomPercent: Int((zoom * 100).rounded()),
                onFit: fitToWindow,
                onActualSize: { setZoom(1) },
                onZoomIn: { setZoom(zoom * 1.25) },
                onZoomOut: { setZoom(zoom / 1.25) },
                onAdd: onAdd
            )
            .padding(18)
        }
        .animation(.smooth(duration: 0.25), value: hoveredFolder)
        .animation(.smooth(duration: 0.25), value: filter)
    }

    // MARK: Cartões

    @ViewBuilder
    private func cardGroup(for item: BoardItem) -> some View {
        let size = BoardLayout.cardSize(for: item.kind)
        if item.kind == .folder {
            HStack(alignment: .top, spacing: 28) {
                cardButton(item, open: [.collection(item.id)])
                    .frame(width: size.width, height: size.height)
                if hoveredFolder == item.id {
                    FolderPeek(folder: item, model: model, hero: hero) { child in
                        onOpen([.collection(item.id), .item(child)])
                    }
                    .transition(.asymmetric(insertion: .scale(scale: 0.85, anchor: .leading).combined(with: .opacity), removal: .opacity))
                }
            }
            .onHover { inside in hoveredFolder = inside ? item.id : (hoveredFolder == item.id ? nil : hoveredFolder) }
        } else {
            cardButton(item, open: [.item(item.id)])
                .frame(width: size.width, height: size.height)
        }
    }

    private func cardButton(_ item: BoardItem, open destinations: [Destination]) -> some View {
        HeroSlot(id: item.id, context: hero) {
            Button {
                onOpen(destinations)
            } label: {
                CardView(item: item, model: model)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.title)
            .contextMenu {
                Button("Abrir") { onOpen(destinations) }
                Divider()
                Button("Apagar", role: .destructive) { model.delete(item.id) }
            }
        }
    }

    /// Esmaece o que não é foco: o resto do mural quando uma pasta está em destaque,
    /// ou o que não combina com o filtro escolhido.
    private func opacity(for item: BoardItem) -> Double {
        if let hoveredFolder, hoveredFolder != item.id { return 0.3 }
        if let filter, !filter.matches(item.kind) { return 0.25 }
        return 1
    }

    // MARK: Zoom

    private func setZoom(_ value: CGFloat, animated: Bool = true) {
        let clamped = min(max(value, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        if animated {
            withAnimation(.smooth(duration: 0.3)) { zoom = clamped }
        } else {
            zoom = clamped
        }
        zoomAtGestureStart = clamped
    }

    private func fitToWindow() {
        let items = model.rootItems
        let maxX = (items.map { $0.position.x + BoardLayout.cardSize(for: $0.kind).width }.max() ?? 400) + 80
        let maxY = (items.map { $0.position.y + BoardLayout.cardSize(for: $0.kind).height }.max() ?? 300) + 80
        guard viewport.width > 0, viewport.height > 0 else { return }
        setZoom(min(viewport.width / maxX, viewport.height / maxY))
        withAnimation(.smooth(duration: 0.3)) { scrollPosition.scrollTo(point: .zero) }
    }
}

/// Prévia de uma pasta ao passar o ponteiro: até seis cartões de dentro, lado a lado.
private struct FolderPeek: View {
    let folder: BoardItem
    let model: BoardModel
    let hero: HeroContext
    var onOpenChild: (UUID) -> Void

    var body: some View {
        let children = Array(model.children(of: folder.id).prefix(6))
        HStack(alignment: .top, spacing: 10) {
            ForEach(children) { child in
                let size = BoardLayout.cardSize(for: child.kind)
                HeroSlot(id: child.id, context: hero) {
                    Button {
                        onOpenChild(child.id)
                    } label: {
                        CardView(item: child, model: model)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(child.title)
                }
                .frame(width: size.width * 0.8, height: size.height * 0.8)
            }
            if children.isEmpty {
                Text("Pasta vazia — abra e cole algo com ⌘V")
                    .font(.label)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
    }
}
