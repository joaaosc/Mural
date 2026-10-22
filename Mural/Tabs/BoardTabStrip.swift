import SwiftUI
import UniformTypeIdentifiers

/// Faixa de abas como a do Safari no layout compacto: uma aba por mural aberto, todas da mesma
/// largura, na mesma linha dos botões da janela. Com abas demais para a largura, a faixa rola.
struct BoardTabStrip: View {
    let tabs: MuralTabs
    /// Largura livre na barra da janela: um item da barra não estica sozinho, ele usa a largura pedida.
    let width: CGFloat

    /// Aba sendo arrastada para mudar de lugar.
    @State private var draggedTab: UUID?

    static let spacing: CGFloat = 4
    static let minimumTabWidth: CGFloat = 90
    static let height: CGFloat = 30

    var body: some View {
        let count = tabs.tabs.count
        let tabWidth = Self.tabWidth(count: count, available: width)
        let fits = CGFloat(count) * tabWidth + Self.spacing * CGFloat(max(0, count - 1)) <= width + 0.5
        ScrollView(.horizontal) {
            HStack(spacing: Self.spacing) {
                ForEach(tabs.tabs) { tab in
                    BoardTabButton(
                        title: tab.title,
                        isSelected: tab.id == tabs.selectedID,
                        canCloseOthers: count > 1,
                        onSelect: { tabs.select(tab.id) },
                        onClose: { tabs.close(tab.id) },
                        onCloseOthers: { tabs.closeOthers(tab.id) },
                        onDelete: { tabs.requestDelete(tab.route, name: tab.title) }
                    )
                    .frame(width: tabWidth, height: Self.height)
                    .onDrag {
                        draggedTab = tab.id
                        return NSItemProvider(object: tab.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: TabReorderDelegate(target: tab.id, tabs: tabs, dragged: $draggedTab))
                }
            }
        }
        .scrollIndicators(.never)
        .scrollDisabled(fits)
        .frame(width: width, height: Self.height, alignment: .leading)
    }

    /// Largura de cada aba: a faixa dividida igualmente, sem passar do mínimo legível.
    static func tabWidth(count: Int, available: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        let shared = (available - spacing * CGFloat(count - 1)) / CGFloat(count)
        return max(minimumTabWidth, shared.rounded(.down))
    }
}

/// Reordena as abas enquanto uma é arrastada por cima das outras, como no Safari.
private struct TabReorderDelegate: DropDelegate {
    let target: UUID
    let tabs: MuralTabs
    @Binding var dragged: UUID?

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != target else { return }
        withAnimation(.smooth(duration: 0.2)) { tabs.moveTab(dragged, to: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }

    func dropExited(info: DropInfo) {}
}

/// Uma aba: o nome do mural no meio e, ao passar o ponteiro, o "×" à esquerda, como no Safari.
struct BoardTabButton: View {
    let title: String
    let isSelected: Bool
    var canCloseOthers = true
    var onSelect: () -> Void
    var onClose: () -> Void
    var onCloseOthers: () -> Void = {}
    var onDelete: () -> Void = {}

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 26)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(background, in: .rect(cornerRadius: 9))
        .overlay(alignment: .leading) {
            if isHovering {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
                .help("Fechar aba (⌘W)")
                .accessibilityLabel("Fechar aba \(title)")
            }
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Fechar aba", action: onClose)
            Button("Fechar outras abas", action: onCloseOthers)
                .disabled(!canCloseOthers)
            Divider()
            Button("Excluir Mural…", role: .destructive, action: onDelete)
        }
        .help(title)
        .accessibilityIdentifier("board-tab")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Fechar aba", onClose)
    }

    private var background: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(.fill.secondary) }
        if isHovering { return AnyShapeStyle(.fill.quaternary) }
        return AnyShapeStyle(.clear)
    }
}

#Preview("Abas", traits: .fixedLayout(width: 900, height: 80)) {
    HStack(spacing: 4) {
        BoardTabButton(title: "Rascunho de exemplo", isSelected: true, onSelect: {}, onClose: {})
        BoardTabButton(title: "Viagem ao Japão", isSelected: false, onSelect: {}, onClose: {})
        BoardTabButton(title: "Obra da casa nova com um nome bem comprido", isSelected: false, onSelect: {}, onClose: {})
    }
    .frame(height: BoardTabStrip.height)
    .padding(24)
    .background { PreviewBackdrop() }
}
