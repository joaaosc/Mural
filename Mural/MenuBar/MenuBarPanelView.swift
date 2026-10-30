import AppKit
import MuralKit
import SwiftUI

/// O conteúdo do painel da barra de menus: a vitrine de murais, a seção de colar o que foi copiado e, embaixo, a
/// fileira de saídas.
///
/// O teclado é do conteúdo (a vitrine e a seção de colar) e anda por etapas (``PanelStage``). Em todas, ←/→ trocam de
/// mural, letras procuram pelo nome, ⌘↩ abre o mural e ⌘V cola com a maneira e a formatação escolhidas (de início, as
/// sugeridas). Na vitrine, onde o painel abre, Return abre o mural do centro. Tab mostra as maneiras de colar e, com
/// texto, outro Tab mostra a formatação; nelas ↑/↓ escolhem e Return cola. ⇧Tab volta uma etapa, e Esc volta à vitrine
/// ou, já nela, fecha o painel. Tab e ⇧Tab só andam entre as etapas: na última, Tab não faz nada, e na primeira, ⇧Tab
/// também não. Os botões do rodapé são só para o mouse (⌘↩ continua abrindo o mural).
struct MenuBarPanelView: View {
    let tabs: MuralTabs
    let model: MenuBarPanelModel
    /// O tocador, para a seção "Tocando agora".
    var playback: MusicPlayback = .shared
    /// Fecha o painel em que a vista está.
    ///
    /// Injetado, e não lido do ambiente: o painel é um `NSPanel` aberto pelo ícone, não uma cena do SwiftUI, e não há
    /// uma ação `dismiss` para ler.
    let close: @MainActor () -> Void
    /// Pede ao painel que tome a nova altura do conteúdo. Injetado pelo mesmo motivo de `close`: o painel é do AppKit e
    /// não acompanha o conteúdo sozinho. Chamado quando a lista carrega e quando muda algo que altera a altura da seção
    /// de colar: o que há para colar, o número de opções e o estado do colar.
    let resize: @MainActor () -> Void
    /// Avisa que a pessoa terminou de arrastar o painel, para o lugar novo ser guardado. Injetado pelo mesmo motivo de
    /// `close`.
    let moved: @MainActor () -> Void

    @FocusState private var contentHasFocus: Bool
    /// O colar em andamento e o fechamento do painel que vem depois dele. Cancelado quando a vista sai, para um colar de
    /// uma abertura anterior não fechar o painel da seguinte.
    @State private var pasteTask: Task<Void, Never>?

    /// Tudo o que muda a altura do conteúdo.
    private struct Layout: Equatable {
        let isLoaded: Bool
        let optionCount: Int
        let formatCount: Int
        let stage: PanelStage
        let clipboard: ClipboardState
        let pasteStatus: PasteStatus
        let showsNowPlaying: Bool
        /// A barra de tempo muda a altura da seção "Tocando agora" (estações não a têm).
        let showsNowPlayingScrubber: Bool
    }

    private var layout: Layout {
        Layout(
            isLoaded: model.isLoaded, optionCount: model.options.count, formatCount: model.formats.count,
            stage: model.stage, clipboard: model.clipboard, pasteStatus: model.pasteStatus,
            showsNowPlaying: playback.source != nil,
            showsNowPlayingScrubber: playback.summary(in: tabs).map(NowPlayingSection.showsScrubber(for:)) ?? false)
    }

    /// O ⇧Tab chega como o caractere de tabulação para trás do AppKit (`NSBackTabCharacter`).
    private static let backTab = KeyEquivalent("\u{19}")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            Divider()
            footer
        }
        .frame(width: PanelMetrics.panelWidth)
        .background { PanelDragArea(onEnded: moved) }
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
    /// O conteúdo tem um único foco para as etapas e comandos de capa; os botões do rodapé não entram na ordem de Tab.
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            stage
                .frame(maxWidth: .infinity)
                .frame(height: BoardCoverflow.height)
                .padding(.top, PanelMetrics.contentPadding)
                .padding(.bottom, PanelMetrics.contentSpacing)
            if let summary = playback.summary(in: tabs) {
                NowPlayingSection(
                    summary: summary, elapsed: { playback.playbackTime }, actions: nowPlayingActions(for: summary))
            }
            if showsPasteSection {
                PasteSection(
                    model: model,
                    choose: { choose($0) },
                    chooseFormat: { chooseFormat($0) },
                    advance: { model.advanceStage() },
                    retreat: { model.retreatStage() })
            }
        }
        .focusable()
        .focused($contentHasFocus)
        .focusEffectDisabled()
        .onAppear { contentHasFocus = true }
        .onDisappear { pasteTask?.cancel() }
        .onKeyPress(.leftArrow, phases: [.down, .repeat]) { _ in step(by: -1) }
        .onKeyPress(.rightArrow, phases: [.down, .repeat]) { _ in step(by: 1) }
        .onKeyPress(.upArrow, phases: [.down, .repeat]) { _ in stepWithinStage(by: -1) }
        .onKeyPress(.downArrow, phases: [.down, .repeat]) { _ in stepWithinStage(by: 1) }
        .onKeyPress(.return, phases: .down) { press in confirm(press) }
        .onKeyPress(keys: [.tab, Self.backTab], phases: .down) { press in tab(press) }
        .onKeyPress(characters: .alphanumerics, phases: .down) { press in type(press) }
        // O painel transforma o ⌘V em `paste:`, que chega aqui como um colar pedido pela pessoa.
        .onPasteCommand(of: PasteboardImporter.acceptedTypes + MusicPasteboardReader.pasteTypes) { _ in pasteNow() }
        .onExitCommand { escape() }
        .onChange(of: layout) { resize() }
    }

    private func nowPlayingActions(for summary: NowPlayingSummary) -> NowPlayingActions {
        NowPlayingActions(
            openSource: {
                close()
                tabs.showBoard(summary.route, title: summary.boardTitle)
            },
            playPause: { Task { await playback.pauseOrResume() } },
            previous: { Task { await playback.skipToPrevious() } },
            next: { Task { await playback.skipToNext() } },
            stop: { playback.stopCurrent() },
            toggleShuffle: { playback.toggleShuffle() },
            cycleRepeat: { playback.cycleRepeat() },
            seek: { playback.seek(to: $0) })
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

    /// ↑/↓ andam pelas maneiras de colar ou pelas formatações, conforme a etapa; na vitrine, a tecla segue adiante.
    private func stepWithinStage(by offset: Int) -> KeyPress.Result {
        switch model.stage {
        case .boards:
            return .ignored
        case .paste:
            model.moveOption(by: offset)
        case .format:
            model.moveFormat(by: offset)
        }
        return .handled
    }

    private func openSelection() -> KeyPress.Result {
        guard model.selectedEntry != nil else { return .ignored }
        open(model.selection)
        return .handled
    }

    /// Na vitrine, Return abre o mural do centro; nas maneiras de colar e na formatação, cola. ⌘Return sempre abre.
    private func confirm(_ press: KeyPress) -> KeyPress.Result {
        guard !press.modifiers.contains(.command), model.stage != .boards else { return openSelection() }
        pasteNow()
        return .handled
    }

    /// Tab e ⇧Tab andam só entre as etapas do conteúdo. Na última etapa, Tab não faz nada; na primeira, ⇧Tab também não.
    /// A tecla é sempre tratada, para o foco nunca chegar aos botões do rodapé.
    private func tab(_ press: KeyPress) -> KeyPress.Result {
        if press.key == Self.backTab || press.modifiers.contains(.shift) {
            if model.stage != .boards { model.retreatStage() }
        } else if model.stages.last != model.stage {
            model.advanceStage()
        }
        return .handled
    }

    /// Esc volta à vitrine e, já nela, fecha o painel.
    private func escape() {
        guard !model.returnToBoards() else { return }
        close()
    }

    // MARK: Colar

    /// Escolhe a maneira de colar da linha clicada e cola.
    private func choose(_ index: Int) {
        model.selectOption(index)
        pasteNow()
    }

    /// Escolhe a formatação da linha clicada e cola.
    private func chooseFormat(_ format: PasteTextFormat) {
        model.selectFormat(format)
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
    /// Os botões são só para o mouse: não entram na ordem de Tab. ⌘↩ abre o mural e ⌘, abre os Ajustes.
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

            // O que é raro (abrir ao iniciar a sessão, o atalho, o lugar do painel, sair) fica nos Ajustes.
            Button("Ajustes…", systemImage: "gearshape", action: openSettings)
                .labelStyle(.iconOnly)
                .keyboardShortcut(",", modifiers: .command)
                .focusable(false)
                .help("Ajustes do Mural (⌘,)")
                .accessibilityIdentifier("menu-bar-settings")
        }
        .buttonStyle(.borderless)
        .padding(PanelMetrics.contentPadding)
    }

    /// Fecha o painel e abre os Ajustes, com o Mural na frente.
    private func openSettings() {
        close()
        SettingsOpener.shared.open()
    }
}
