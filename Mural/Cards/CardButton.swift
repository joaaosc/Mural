import AppKit
import MuralKit
import SwiftUI

/// Cartão clicável do mural, da prévia de pasta e de dentro da pasta: abre o item,
/// participa da transição de "crescer do cartão" e oferece Abrir, Mover e Apagar… no menu de
/// contexto, com confirmação antes de apagar. Com o seletor de ⌘ aberto, o clique marca.
struct CardButton: View {
    let item: BoardItem
    let model: BoardModel
    let hero: HeroContext
    var onOpen: () -> Void
    var onDelete: ((UUID) -> Void)? = nil
    var onMoveToBoard: ((UUID) -> Void)? = nil
    var onMoveIntoFolder: ((UUID, UUID) -> Void)? = nil
    var onMoveUp: ((UUID) -> Void)? = nil
    /// `nil` onde não há seletor (a prévia de pasta que aparece ao passar o ponteiro).
    var selection: CardSelection? = nil

    @State private var isConfirmingDelete = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.linkPreviewCoordinator) private var linkPreviewCoordinator

    private var isSelected: Bool { selection?.selected.contains(item.id) ?? false }

    var body: some View {
        HeroSlot(id: item.id, context: hero) {
            Button(action: activate) {
                CardView(item: item, model: model)
            }
            .buttonStyle(.plain)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.cardCorner)
                        .strokeBorder(.tint, lineWidth: 3)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                if selection?.isActive == true {
                    SelectionBadge(isSelected: isSelected)
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel(item.title)
            .accessibilityValue(item.link?.displaySiteName ?? "", isEnabled: item.kind == .link)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .contextMenu {
                Button("Abrir", action: onOpen)
                linkMenu
                moveMenu
                Divider()
                Button("Apagar…", role: .destructive) { isConfirmingDelete = true }
            }
            .confirmationDialog("Apagar “\(item.title)”?", isPresented: $isConfirmingDelete) {
                Button("Apagar", role: .destructive) {
                    withAnimation(reduceMotion ? nil : .smooth) { onDelete?(item.id) ?? model.delete(item.id) }
                }
            } message: {
                Text(ItemKind.deleteWarning(for: item, childCount: model.descendantCount(of: item.id)))
            }
        }
    }

    /// Com o seletor aberto (ou ⌘ segurado no clique), o clique marca o cartão em vez de abrir.
    private func activate() {
        if let selection, selection.isActive || NSEvent.modifierFlags.contains(.command) {
            selection.toggle(item.id)
        } else {
            onOpen()
        }
    }

    /// Só para link: abrir a página no navegador, copiar o endereço e buscar a prévia de novo.
    @ViewBuilder
    private var linkMenu: some View {
        if let url = item.browserURL {
            Button("Abrir no navegador") { NSWorkspace.shared.open(url) }
            Button("Copiar link") { PasteboardExporter.copy(item, from: model) }
            Button("Atualizar prévia") { linkPreviewCoordinator?.request([item.id], force: true) }
                .disabled(linkPreviewCoordinator == nil)
        }
    }

    /// Alternativa ao arrasto: devolver ao mural (ou à pasta de cima) um cartão guardado e levar
    /// qualquer cartão, pasta inclusive, a outra pasta, de qualquer nível.
    @ViewBuilder
    private var moveMenu: some View {
        if let parentID = item.parentID {
            Button("Mover para o mural") {
                withAnimation(reduceMotion ? nil : .smooth) { onMoveToBoard?(item.id) ?? model.moveToBoard(item.id) }
            }
            if model.item(id: parentID)?.parentID != nil {
                Button("Mover para a pasta de cima") {
                    withAnimation(reduceMotion ? nil : .smooth) { onMoveUp?(item.id) ?? model.moveUp(item.id) }
                }
            }
        }
        let destinations = model.board.folderDestinations(for: item.id)
        if !destinations.isEmpty {
            Menu("Mover para a pasta") {
                ForEach(destinations, id: \.id) { destination in
                    Button(destination.title) {
                        withAnimation(reduceMotion ? nil : .smooth) {
                            onMoveIntoFolder?(item.id, destination.id)
                                ?? model.moveIntoFolder(item.id, folderID: destination.id)
                        }
                    }
                }
            }
        }
    }
}
