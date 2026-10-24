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
    /// Pede o nome novo do cartão; `nil` esconde a ação (por exemplo, na prévia de pasta).
    var onRename: ((UUID) -> Void)? = nil
    /// Abre a edição da legenda persistente; `nil` esconde a ação na prévia de pasta.
    var onEditCaption: ((UUID) -> Void)? = nil
    /// Muda o tamanho de um post-it solto no mural (`nil` volta ao padrão); `nil` esconde o submenu "Tamanho". Pastas e prévias
    /// de pasta não passam: o post-it guardado numa pasta não muda de tamanho.
    var onResize: ((UUID, BoardSize?) -> Void)? = nil
    /// Marca ou reabre o lembrete; `nil` onde a bolinha não é clicável (a prévia de pasta).
    var onToggleReminder: ((UUID) -> Void)? = nil
    /// Toca ou pausa a música; `nil` onde o botão não aparece (a prévia de pasta).
    var onToggleMusic: ((UUID) -> Void)? = nil
    var musicPhase: MusicCardPhase = .idle
    /// `nil` onde não há seletor (a prévia de pasta que aparece ao passar o ponteiro).
    var selection: CardSelection? = nil

    @State private var isConfirmingDelete = false
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.linkPreviewCoordinator) private var linkPreviewCoordinator

    private var isSelected: Bool { selection?.selected.contains(item.id) ?? false }

    var body: some View {
        HeroSlot(id: item.id, context: hero) {
            cardSurface
        }
    }

    /// Mantém o `ConfirmationDialog` fora da árvore enquanto nenhum cartão está pedindo confirmação.
    /// Cada cartão continua anexando o diálogo no instante em que `isConfirmingDelete` muda para `true`.
    @ViewBuilder
    private var cardSurface: some View {
        let card = Button(action: activate) {
            ZStack(alignment: .bottomLeading) {
                CardView(item: item, model: model)
                CardCaptionView(caption: item.caption)
            }
        }
        .buttonStyle(.plain)
        // Só no botão do cartão: aplicado depois das sobreposições, o rótulo cobriria também o da bolinha.
        .accessibilityLabel(item.title)
        .accessibilityValue(accessibilityDetail, isEnabled: !accessibilityDetail.isEmpty)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.cardCorner)
                    .strokeBorder(.tint, lineWidth: 3)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topLeading) {
            if selection?.isActive == true {
                SelectionBadge(isSelected: isSelected)
                    .offset(x: -SelectionBadge.outset, y: -SelectionBadge.outset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topLeading) { reminderToggle }
        .overlay(alignment: .topLeading) { musicToggle }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Abrir", action: onOpen)
            if let onRename {
                Button("Renomear…") { onRename(item.id) }
            }
            if let onEditCaption {
                Button(item.caption == nil ? "Adicionar legenda…" : "Editar legenda…") {
                    onEditCaption(item.id)
                }
            }
            linkMenu
            musicMenu
            notesMenu
            moveMenu
            sizeMenu
            Divider()
            colorMenu
            Divider()
            Button("Apagar…", role: .destructive) { isConfirmingDelete = true }
        }

        if isConfirmingDelete {
            card.confirmationDialog("Apagar “\(item.title)”?", isPresented: $isConfirmingDelete) {
                Button("Apagar", role: .destructive) {
                    withAnimation(reduceMotion ? nil : .smooth) { onDelete?(item.id) ?? model.delete(item.id) }
                }
            } message: {
                Text(ItemKind.deleteWarning(for: item, childCount: model.descendantCount(of: item.id)))
            }
        } else {
            card
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

    /// Tocar/pausar sobre o canto do cartão de música: aparece com o ponteiro em cima ou enquanto toca.
    @ViewBuilder
    private var musicToggle: some View {
        if item.kind == .music, let onToggleMusic, selection?.isActive != true, isHovering || musicPhase != .idle {
            let title = musicPhase == .playing ? "Pausar" : musicPhase == .loading ? "Carregando" : "Tocar"
            Button {
                onToggleMusic(item.id)
            } label: {
                ZStack {
                    if musicPhase == .loading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: musicPhase == .playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .frame(width: 26, height: 26)
                .background(.regularMaterial, in: .circle)
                .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .padding(6)
            .accessibilityLabel(title)
            .accessibilityIdentifier("music-toggle")
            .help(title)
        }
    }

    /// Site do link e cor da tag, separados por vírgula; vazio quando o cartão não tem nenhum dos dois.
    private var accessibilityDetail: String {
        var parts: [String] = []
        if let caption = item.caption, !caption.isEmpty { parts.append(caption) }
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

    /// Só para música: tocar ou pausar, abrir no Música e, com endereço, copiar o link do Apple Music.
    @ViewBuilder
    private var musicMenu: some View {
        if item.kind == .music {
            if let onToggleMusic {
                Button(musicPhase == .playing ? "Pausar" : "Tocar") { onToggleMusic(item.id) }
            }
            Button("Abrir no Música") { if let music = item.music { MusicOpener.open(music) } }
        }
        if item.kind == .music, item.music?.url != nil {
            Button("Copiar link") { PasteboardExporter.copy(item, from: model) }
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
        let destinations = model.folderDestinations(for: item.id)
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

    /// Só no post-it solto no mural: os tamanhos predefinidos e a volta ao padrão, a alternativa ao arrasto do canto do cartão.
    @ViewBuilder
    private var sizeMenu: some View {
        if let onResize, item.kind == .sticky {
            BoardSizeMenu(
                sides: BoardLayout.stickyPresetSides,
                isStandard: BoardLayout.size(of: item) == BoardLayout.cardSize(for: item.kind)
            ) { size in
                withAnimation(reduceMotion ? nil : .smooth) { onResize(item.id, size) }
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
