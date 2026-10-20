import SwiftUI

/// Itens de menu do Mural: importar em Arquivo e zoom em Visualizar.
struct MuralCommands: Commands {
    let state: AppCommandsState

    @FocusedValue(CanvasZoomController.self) private var zoom

    var body: some Commands {
        CommandGroup(replacing: .importExport) {
            Button("Importar…") { state.isImporterPresented = true }
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
        }
    }
}
