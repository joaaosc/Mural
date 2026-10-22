import AppKit
import MuralKit
import SwiftUI

/// Itens de menu do Mural. Todas as ações são encaminhadas à cena focada;
/// nenhuma referência a uma janela ou a um mural fica global no aplicativo.
struct MuralCommands: Commands {
    @FocusedValue(CanvasZoomController.self) private var zoom
    @FocusedValue(FocusedBoardActions.self) private var actions
    @FocusedValue(\.markdownFormatting) private var formatting
    @Environment(\.muralCommandCoordinator) private var coordinator
    @Environment(\.openWindow) private var openWindow

    private func requestOrOpenLibrary(
        _ intent: MuralCommandIntent,
        focusedAction: (FocusedBoardActions) -> Void
    ) {
        if let actions {
            focusedAction(actions)
        } else {
            coordinator?.submit(intent)
            openWindow(value: BoardRoute.library)
        }
    }

    var body: some Commands {
        // Os comandos existem mesmo sem janelas: daqui o delegate consegue abrir a biblioteca.
        let _ = LibraryWindowOpener.shared.register { [openWindow] in openWindow(value: BoardRoute.library) }
        CommandGroup(replacing: .newItem) {
            Button("Novo Mural…") {
                requestOrOpenLibrary(.newBoard) { $0.newBoard() }
            }
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
            Button("Abrir Mural…") {
                requestOrOpenLibrary(.openMural) { $0.openMural() }
            }
            .keyboardShortcut("o", modifiers: .command)
            Button("Adicionar Arquivos…", action: { actions?.addFiles() })
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(!(actions?.canAddFiles ?? false))
        }
        CommandGroup(replacing: .saveItem) {
            // Este grupo também traz o "Fechar" do macOS; ao substituí-lo, o ⌘W sumia.
            Button("Fechar") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: .command)
            Divider()
            Button("Salvar Mural…", action: { actions?.saveDraft() })
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!(actions?.canSaveDraft ?? false))
            Button("Salvar uma Cópia…", action: { actions?.saveCopy() })
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!(actions?.canSaveCopy ?? false))
            Button("Renomear Mural…", action: { actions?.rename() })
                .disabled(!(actions?.canRename ?? false))
            Button("Retomar Rascunho de Exemplo", action: { actions?.resumeDraft() })
                .disabled(!(actions?.canResumeDraft ?? false))
        }
        CommandGroup(after: .toolbar) {
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
            Button("Tentar novamente", action: { actions?.retryFlush() })
                .disabled(actions == nil)
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
