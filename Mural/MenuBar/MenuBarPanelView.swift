import AppKit
import SwiftUI

/// O conteúdo do painel da barra de menus: a vitrine de murais, a seção de colar o que foi copiado e, embaixo, a
/// fileira de saídas.
///
/// O teclado é do conteúdo (a vitrine e a seção de colar): ←/→ trocam de mural, ↑/↓ escolhem como colar, letras procuram
/// pelo nome, Return cola o que está copiado (ou abre o mural, se não há o que colar), ⌘↩ abre e ⌘V cola. Os botões do
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
    /// não acompanha o conteúdo sozinho. Chamado quando a lista carrega e quando muda algo que altera a altura da seção
    /// de colar: o que há para colar, o número de opções e o estado do colar.
    let resize: @MainActor () -> Void

    @FocusState private var isFocused: Bool
    /// O colar em andamento e o fechamento do painel que vem depois dele. Cancelado quando a vista sai, para um colar de
    /// uma abertura anterior não fechar o painel da seguinte.
    @State private var pasteTask: Task<Void, Never>?

    /// Tudo o que muda a altura do conteúdo.
    private struct Layout: Equatable {
        let isLoaded: Bool
        let optionCount: Int
        let clipboard: ClipboardState
        let pasteStatus: PasteStatus
    }

    private var layout: Layout {
        Layout(
            isLoaded: model.isLoaded, optionCount: model.options.count, clipboard: model.clipboard,
            pasteStatus: model.pasteStatus)
    }

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

    /// A vitrine, ou o que ocupa o lugar dela, e a seção de colar embaixo. A moldura da vitrine é a mesma em todos os
    /// estados, e a altura também, para ela não pular quando a lista termina de carregar; a seção é que dá a altura
    /// variável do painel.
    ///
    /// O teclado de tudo isso é deste contêiner só, e a seção não toma o foco: ela é feita de alvos de clique.
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            stage
                .frame(maxWidth: .infinity)
                .frame(height: BoardCoverflow.height)
                .padding(.top, PanelMetrics.contentPadding)
                .padding(.bottom, PanelMetrics.contentSpacing)
            if showsPasteSection {
                PasteSection(model: model, choose: { choose($0) })
            }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear { isFocused = true }
        .onDisappear { pasteTask?.cancel() }
        .onKeyPress(.leftArrow, phases: [.down, .repeat]) { _ in step(by: -1) }
        .onKeyPress(.rightArrow, phases: [.down, .repeat]) { _ in step(by: 1) }
        .onKeyPress(.upArrow, phases: [.down, .repeat]) { _ in stepOption(by: -1) }
        .onKeyPress(.downArrow, phases: [.down, .repeat]) { _ in stepOption(by: 1) }
        .onKeyPress(.return, phases: .down) { press in confirm(press) }
        .onKeyPress(characters: .alphanumerics, phases: .down) { press in type(press) }
        // O painel transforma o ⌘V em `paste:`, que chega aqui como um colar pedido pela pessoa.
        .onPasteCommand(of: PasteboardImporter.acceptedTypes + MusicPasteboardReader.pasteTypes) { _ in pasteNow() }
        .onExitCommand { close() }
        .onChange(of: layout) { resize() }
    }

    /// A seção de colar só aparece com murais na vitrine: sem eles não há para onde colar.
    private var showsPasteSection: Bool {
        model.isLoaded && model.loadError == nil && !model.entries.isEmpty
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

    /// ↑/↓ andam pelas opções de colar; sem opções, a tecla segue adiante.
    private func stepOption(by offset: Int) -> KeyPress.Result {
        guard !model.options.isEmpty else { return .ignored }
        model.moveOption(by: offset)
        return .handled
    }

    private func openSelection() -> KeyPress.Result {
        guard model.selectedEntry != nil else { return .ignored }
        open(model.selection)
        return .handled
    }

    /// Return cola o que está copiado, se há como colar; ⌘Return, e Return sem nada para colar, abrem o mural.
    private func confirm(_ press: KeyPress) -> KeyPress.Result {
        guard !press.modifiers.contains(.command), model.canPaste else { return openSelection() }
        pasteNow()
        return .handled
    }

    // MARK: Colar

    /// Escolhe a opção da linha clicada e cola.
    private func choose(_ index: Int) {
        model.selectOption(index)
        pasteNow()
    }

    /// Cola o que está copiado no mural do centro e, feito o colar, fecha o painel.
    ///
    /// A leitura da área de transferência (`readForPaste()`) é síncrona e acontece antes de qualquer `await`, dentro do
    /// tratamento do ⌘V, do Return ou do clique: o macOS sempre deixa ler num colar pedido pela pessoa e fora dele pode
    /// perguntar "Permitir colar?". Só a entrega, assíncrona, vai para a `Task`. Depois de colado, o painel espera um
    /// segundo para a pessoa ver "Colado em …" e fecha.
    private func pasteNow() {
        guard model.readForPaste() else { return }
        pasteTask = Task {
            guard await model.paste() else { return }
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            close()
        }
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
