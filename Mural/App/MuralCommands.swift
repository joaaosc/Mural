import AppKit
import MuralKit
import SwiftUI

/// Itens de menu do Mural. O que é do mural aberto vai à aba focada (`FocusedBoardActions`); abas,
/// novo mural e importação vão às abas da janela (`MuralTabs`), que existem mesmo sem janela.
struct MuralCommands: Commands {
    let tabs: MuralTabs

    @FocusedValue(CanvasZoomController.self) private var zoom
    @FocusedValue(FocusedBoardActions.self) private var actions
    @FocusedValue(\.markdownFormatting) private var formatting
    @FocusedValue(\.textEditorActions) private var textEditor
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    /// ⌘W fecha a aba, como no Safari; fora da janela do Mural (um painel, por exemplo), fecha o que está na frente.
    private func closeTab() {
        if let key = NSApp.keyWindow, key !== tabs.window {
            key.performClose(nil)
        } else {
            tabs.closeSelected()
        }
    }

    #if DEBUG
    /// Arquivo › Preparar o Esquema do iCloud…: grava o esquema de exemplo no iCloud de desenvolvimento e avisa o resultado
    /// (`CloudSyncController.prepareSchema()`). Não existe nas compilações de distribuição.
    private func prepareCloudSchema() {
        guard let sync = CloudSyncController.current else { return }
        Task {
            do {
                try await sync.prepareSchema()
                sync.postSchemaNotice(
                    "O esquema foi gravado no ambiente de desenvolvimento. "
                        + "Publique-o em produção no CloudKit Console (Deploy Schema Changes).")
            } catch {
                sync.postSchemaNotice("Não foi possível preparar o esquema: \(error.localizedDescription)")
            }
        }
    }
    #endif

    var body: some Commands {
        // Os comandos existem mesmo sem janelas: daqui as abas e o delegate conseguem abrir a janela.
        let _ = tabs.registerWindowOpener { [openWindow] in openWindow(id: MuralWindowView.sceneID) }
        let _ = MainWindowOpener.shared.register { [tabs] in tabs.showWindow() }
        // A engrenagem do painel da barra de menus é do AppKit e abre os Ajustes por aqui.
        let _ = SettingsOpener.shared.register { [openSettings] in openSettings() }
        // O painel da barra de menus também abre o editor de texto por aqui.
        let _ = TextEditorOpener.shared.register { [openWindow] in openWindow(id: TextEditorWindow.sceneID) }
        CommandGroup(after: .appInfo) {
            // Começa desligada; o mesmo estado da aba Geral dos Ajustes. O estado é lido aqui, e
            // não dentro do `Binding`, para o menu acompanhar a mudança.
            let loginItem = LoginItemModel.shared
            let isOn = loginItem.isOn
            Toggle("Abrir ao Iniciar Sessão", isOn: Binding(get: { isOn }, set: { loginItem.setOn($0) }))
        }
        CommandGroup(replacing: .newItem) {
            Button("Novo Mural…") { tabs.requestNewBoard() }
                .keyboardShortcut("n", modifiers: .command)
        }
        CommandGroup(after: .newItem) {
            Section {
                Button("Novo card de texto", action: { actions?.newNote() })
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(!(actions?.canCreateContent ?? false))
                Button("Novo sticker", action: { actions?.newSticky() })
                    .keyboardShortcut("n", modifiers: [.command, .option])
                    .disabled(!(actions?.canCreateContent ?? false))
                // ⌃⌘N, como a pasta do Finder: ⇧⌘N e ⌥⌘N já criam card e sticker.
                Button("Nova pasta…", action: { actions?.newFolder() })
                    .keyboardShortcut("n", modifiers: [.command, .control])
                    .disabled(!(actions?.canCreateFolder ?? false))
            }
        }
        CommandGroup(replacing: .importExport) {
            Button("Abrir Mural…") { tabs.requestOpenPackage() }
                .keyboardShortcut("o", modifiers: .command)
            Button("Adicionar Arquivos…", action: { actions?.addFiles() })
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(!(actions?.canAddFiles ?? false))
            Button("Adicionar Lembretes…", action: { actions?.addReminders() })
                .disabled(!(actions?.canCreateContent ?? false))
        }
        CommandGroup(replacing: .saveItem) {
            // Este grupo também traz o "Fechar" do macOS; ao substituí-lo, o ⌘W sumia.
            Button("Fechar Aba", action: closeTab)
                .keyboardShortcut("w", modifiers: .command)
            Button("Fechar Janela") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            Divider()
            Button("Salvar Mural…", action: { actions?.saveDraft() })
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!(actions?.canSaveDraft ?? false))
            Button("Salvar uma Cópia…", action: { actions?.saveCopy() })
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!(actions?.canSaveCopy ?? false))
            Button("Renomear Mural…", action: { actions?.rename() })
                .disabled(!(actions?.canRename ?? false))
            // Habilitado quando o botão Compartilhar da barra está: sem o entitlement de CloudKit (`CloudSyncController.current` é
            // `nil`) o item fica desabilitado; com `-uiTesting` o controlador existe e usa o iCloud falso.
            Button("Compartilhar…") { tabs.requestShareSelected() }
                .disabled(!tabs.canShareSelected)
            #if DEBUG
            // Só nas compilações de desenvolvimento, e só com o iCloud de verdade (`CloudSyncMode.cloudKit`).
            Button("Preparar o Esquema do iCloud…", action: prepareCloudSchema)
                .disabled(CloudSyncController.current?.mode != .cloudKit)
            #endif
            Button(BoardDeletionRequest.menuTitle(role: tabs.role(for: tabs.selected?.session.cloud))) {
                Task { await tabs.requestDeleteSelected() }
            }
            .disabled(tabs.selected == nil)
            Button("Retomar Rascunho de Exemplo") { Task { await tabs.resumeDraft() } }
                .disabled(!tabs.resumeDraftAvailable)
            Button("Revisar Rascunhos de Janelas Fechadas…") {
                OpenBoardSessions.shared.reviewRetainedDrafts()
            }
        }
        CommandGroup(replacing: .sidebar) {
            Button(tabs.isSidebarVisible ? "Ocultar Barra Lateral" : "Mostrar Barra Lateral") {
                tabs.isSidebarVisible.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
        }
        CommandGroup(after: .toolbar) {
            // Como "Mostrar Todas as Abas" do Safari: a janela com a barra lateral de murais.
            Button("Mostrar Todos os Murais") { tabs.showAllMurals() }
                .keyboardShortcut("\\", modifiers: [.command, .shift])
            // O mesmo painel do ícone na barra de menus, aberto no meio da tela.
            Button("Abrir Painel de Murais") { MenuBarController.shared.presentCentered() }
            Button("Abrir Editor de Texto") { TextEditorOpener.shared.open() }
            Section {
                Button("Aproximar") { zoom?.zoomIn() }
                    .keyboardShortcut("=", modifiers: .command)
                Button("Afastar") { zoom?.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Tamanho real") { zoom?.actualSize() }
                    .keyboardShortcut("0", modifiers: .command)
                Button("Ajustar à janela") { zoom?.fitToWindow() }
                    .keyboardShortcut("9", modifiers: .command)
            }
            .disabled(zoom == nil)
            Section {
                // Mosaico como num gerenciador de janelas; ⌘Z devolve os cartões.
                Button("Organizar Mural", systemImage: "rectangle.split.2x2", action: { actions?.tileBoard() })
                    .keyboardShortcut("o", modifiers: [.command, .control])
                    .disabled(!(actions?.canTileBoard ?? false))
            }
            Button("Tentar novamente", action: { actions?.retryFlush() })
                .disabled(actions == nil)
        }
        CommandGroup(after: .textEditing) {
            // As formatações e o lembrete do editor de texto, os mesmos botões da barra dele; valem com a janela dele em foco.
            Section {
                ForEach(TextEditorWording.formats) { format in
                    Button(format.title, systemImage: format.symbolName) { textEditor?.applyFormat(format) }
                        .keyboardShortcut(
                            TextEditorWording.shortcut(for: format).map { KeyEquivalent($0) }.map {
                                KeyboardShortcut($0, modifiers: [.command, .shift])
                            })
                }
                Button("Inserir Lembrete…", systemImage: "checklist.checked") { textEditor?.insertReminder() }
            }
            .disabled(textEditor == nil)
            Button("Colar no Mural…", systemImage: "arrow.down.doc") { textEditor?.requestPaste() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!(textEditor?.canPaste ?? false))
        }
        CommandGroup(before: .windowArrangement) {
            Button("Mostrar Aba Seguinte") { tabs.selectNext() }
                .keyboardShortcut(.tab, modifiers: .control)
                .disabled(tabs.tabs.count < 2)
            Button("Mostrar Aba Anterior") { tabs.selectPrevious() }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                .disabled(tabs.tabs.count < 2)
            Divider()
        }
        CommandMenu("Formatar") {
            Section {
                Button("Negrito") { formatting?.apply(.bold) }
                    .keyboardShortcut("b", modifiers: .command)
                Button("Itálico") { formatting?.apply(.italic) }
                    .keyboardShortcut("i", modifiers: .command)
            }
            .disabled(formatting == nil)
        }
    }
}
