import AppKit
import SwiftUI

/// O conteúdo do painel da barra de menus: a vitrine de murais e, embaixo, a fileira de saídas.
///
/// O teclado é do conteúdo (a vitrine): setas trocam de mural, letras procuram pelo nome, Return abre. Os botões do
/// rodapé são alvos de clique.
struct MenuBarPanelView: View {
    let tabs: MuralTabs
    let model: MenuBarPanelModel
    /// Fecha o painel em que a vista está.
    ///
    /// Injetado, e não lido do ambiente: o painel é um `NSPanel` aberto pelo ícone, não uma cena do SwiftUI, e não há
    /// uma ação `dismiss` para ler.
    let close: @MainActor () -> Void
    /// Pede ao painel que tome a nova altura do conteúdo. Injetado pelo mesmo motivo de `close`: o painel é do AppKit e
    /// não acompanha o conteúdo sozinho. Chamado depois que a lista carrega; como todos os estados do conteúdo têm a
    /// mesma altura, em geral o painel já está no tamanho certo e nada muda.
    let resize: @MainActor () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            Divider()
            footer
        }
        .frame(width: PanelMetrics.panelWidth)
        .task {
            await model.load()
            resize()
        }
    }

    // MARK: Conteúdo

    /// A vitrine, ou o que ocupa o lugar dela. A moldura é a mesma em todos os estados, e a altura também, para o painel
    /// não pular quando a lista termina de carregar.
    private var content: some View {
        stage
            .frame(maxWidth: .infinity)
            .frame(height: BoardCoverflow.height)
            .padding(.top, PanelMetrics.contentPadding)
            .padding(.bottom, PanelMetrics.contentSpacing)
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onAppear { isFocused = true }
            .onKeyPress(.leftArrow, phases: [.down, .repeat]) { _ in step(by: -1) }
            .onKeyPress(.rightArrow, phases: [.down, .repeat]) { _ in step(by: 1) }
            // Por ora o Return só abre; quando houver algo copiado, ele passa a colar.
            .onKeyPress(.return, phases: .down) { _ in openSelection() }
            .onKeyPress(characters: .alphanumerics, phases: .down) { press in type(press) }
            .onExitCommand { close() }
    }

    @ViewBuilder
    private var stage: some View {
        if let error = model.loadError {
            ContentUnavailableView(
                "Não foi possível ler os murais", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if !model.isLoaded {
            Color.clear
        } else if model.entries.isEmpty {
            emptyLibrary
        } else {
            BoardCoverflow(
                entries: model.entries,
                selection: model.selection,
                covers: model.covers.images,
                onSelect: { model.select($0) },
                onOpen: { open($0) })
        }
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("Nenhum mural ainda", systemImage: "rectangle.on.rectangle")
        } description: {
            Text("Crie um mural para colar coisas nele daqui.")
        } actions: {
            Button("Novo mural…") {
                close()
                tabs.requestNewBoard()
            }
            .focusable(false)
            .accessibilityIdentifier("menu-bar-empty-new-board")
        }
    }

    // MARK: Teclado e abrir

    private func step(by offset: Int) -> KeyPress.Result {
        model.move(by: offset)
        return .handled
    }

    private func openSelection() -> KeyPress.Result {
        guard model.selectedEntry != nil else { return .ignored }
        open(model.selection)
        return .handled
    }

    /// Letras, e só elas: com ⌘, ⌃ ou ⌥ a tecla é de um atalho e segue adiante. O Shift não conta, nem o Caps Lock (o
    /// painel também o ignora ao tratar o ⌘V).
    private func type(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.subtracting([.shift, .capsLock]).isEmpty else { return .ignored }
        model.type(press.characters)
        return .handled
    }

    /// Fecha o painel e abre o mural no app. O mesmo caminho serve ao botão, ao Return e ao clique na capa do centro.
    private func open(_ index: Int) {
        close()
        model.open(index, in: tabs)
    }

    // MARK: Rodapé

    /// A fileira de saídas.
    ///
    /// Nada daqui entra na ordem do Tab: o teclado do painel é do conteúdo, e estes são alvos de clique.
    /// `focusable(false)` é o que diz isso.
    private var footer: some View {
        HStack {
            Button("Abrir mural", systemImage: "arrow.up.forward.app") {
                open(model.selection)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.selectedEntry == nil)
            .focusable(false)
            .help("Abrir o mural no app (⌘↩)")
            .accessibilityIdentifier("menu-bar-open-board")

            Button("Novo mural…", systemImage: "plus") {
                close()
                tabs.requestNewBoard()
            }
            .focusable(false)
            .help("Criar um mural novo")
            .accessibilityIdentifier("menu-bar-new-board")

            Button("Todos os murais", systemImage: "sidebar.left") {
                close()
                tabs.showAllMurals()
            }
            .focusable(false)
            .help("Mostrar a janela do Mural com a lista de todos os murais")
            .accessibilityIdentifier("menu-bar-show-all")

            Spacer()

            Button("Sair do Mural", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
            .labelStyle(.iconOnly)
            .focusable(false)
            .help("Sair do Mural")
            .accessibilityIdentifier("menu-bar-quit")
        }
        .buttonStyle(.borderless)
        .padding(PanelMetrics.contentPadding)
    }
}
