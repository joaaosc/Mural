import SwiftUI

/// Itens de menu do Mural: importar em Arquivo e zoom em Visualizar.
struct MuralCommands: Commands {
    @FocusedValue(CanvasZoomController.self) private var zoom
    @FocusedValue(FocusedBoardActions.self) private var actions

    var body: some Commands {
        CommandGroup(replacing: .importExport) {
            Button("Importar…", action: { actions?.addFiles() })
                .keyboardShortcut("i", modifiers: [.command, .shift])
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
    }
}
