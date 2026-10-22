import AppKit
import MuralKit
import SwiftUI

/// Cartão clicável do mural, da prévia de pasta e de dentro da pasta: abre o item,
/// participa da transição de "crescer do cartão" e oferece Abrir, Mover, Cor e Apagar… no menu de
/// contexto, com confirmação antes de apagar. Com o seletor de ⌘ aberto, o clique marca.
/// A cor escolhida vai no valor de acessibilidade, já que o visual (papel tingido ou bolinha) não é lido.
struct CardButton: View {
    let item: BoardItem
    let model: BoardModel
    let hero: HeroContext
    var onOpen: () -> Void
    var onDelete: ((UUID) -> Void)? = nil
    var onMoveToBoard: ((UUID) -> Void)? = nil
    var onMoveIntoFolder: ((UUID, UUID) -> Void)? = nil
    var onSetColorTag: ((UUID, TagColor?) -> Void)? = nil
    var onMoveUp: ((UUID) -> Void)? = nil
    /// Marca ou reabre o lembrete; `nil` onde a bolinha não é clicável (a prévia de pasta).
    var onToggleReminder: ((UUID) -> Void)? = nil
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
            .overlay(alignment: .topLeading) { reminderToggle }
            .accessibilityLabel(item.title)
            .accessibilityValue(accessibilityDetail, isEnabled: !accessibilityDetail.isEmpty)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .contextMenu {
                Button("Abrir", action: onOpen)
                linkMenu
                notesMenu
                moveMenu
                Divider()
                colorMenu
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

    /// Botão sobre a bolinha do lembrete, fora do botão do cartão (botão dentro de botão não recebe o clique).
    /// Com o seletor de ⌘ aberto some, e o clique marca o cartão.
    @ViewBuilder
    private var reminderToggle: some View {
        if item.kind == .reminder, let reminder = item.reminder, let onToggleReminder, selection?.isActive != true {
            Button {
                onToggleReminder(item.id)
            } label: {
                Color.clear.frame(width: 22, height: 22).contentShape(.circle)
            }
            .buttonStyle(.plain)
            .padding(4)
            .accessibilityLabel(reminder.isCompleted ? "Reabrir" : "Marcar como concluído")
            .accessibilityIdentifier("reminder-toggle")
        }
    }

    /// Site do link e cor da tag, separados por vírgula; vazio quando o cartão não tem nenhum dos dois.
    private var accessibilityDetail: String {
        var parts: [String] = []
        if item.kind == .link, let site = item.link?.displaySiteName, !site.isEmpty { parts.append(site) }
        if let color = item.colorTag { parts.append("Cor: \(color.displayName)") }
        return parts.joined(separator: ", ")
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

    /// Nota, post-it e lista: mandar o texto ao app Notas.
    @ViewBuilder
    private var notesMenu: some View {
        if [.text, .sticky, .checklist].contains(item.kind) {
            Button("Salvar no Notas") { NotesSharing().share(item, model: model, from: nil) }
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

    /// Fileira de bolinhas como as tags do Finder. Tocar na cor que o cartão já tem tira a cor.
    @ViewBuilder
    private var colorMenu: some View {
        Picker("Cor", selection: colorTagBinding) {
            ForEach(TagColor.allCases) { color in
                Label(color.displayName, systemImage: "circle.fill")
                    .tint(color.color)
                    .tag(Optional(color))
            }
        }
        .pickerStyle(.palette)
        if item.colorTag != nil {
            Button("Remover cor") { setColorTag(nil) }
        }
    }

    private var colorTagBinding: Binding<TagColor?> {
        Binding(
            get: { item.colorTag },
            set: { newValue in setColorTag(newValue == item.colorTag ? nil : newValue) }
        )
    }

    private func setColorTag(_ color: TagColor?) {
        withAnimation(reduceMotion ? nil : .smooth) {
            if let onSetColorTag {
                onSetColorTag(item.id, color)
            } else {
                _ = model.setColorTag(color, for: item.id)
            }
        }
    }
}
