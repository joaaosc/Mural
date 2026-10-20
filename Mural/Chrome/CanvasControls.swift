import SwiftUI

/// Controles do canto inferior direito do mural: menu de visão (zoom) e adicionar.
struct CanvasControls: View {
    var zoomPercent: Int
    var onFit: () -> Void
    var onActualSize: () -> Void
    var onZoomIn: () -> Void
    var onZoomOut: () -> Void
    var onAdd: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Menu {
                    Button("Ajustar à janela", action: onFit)
                        .keyboardShortcut("0", modifiers: .command)
                    Button("Tamanho real", action: onActualSize)
                        .keyboardShortcut("1", modifiers: .command)
                    Divider()
                    Button("Aproximar", action: onZoomIn)
                        .keyboardShortcut("=", modifiers: .command)
                    Button("Afastar", action: onZoomOut)
                        .keyboardShortcut("-", modifiers: .command)
                } label: {
                    Label("Visão: \(zoomPercent)%", systemImage: "house")
                        .labelStyle(.iconOnly)
                }
                .menuIndicator(.visible)
                .menuStyle(.button)
                .buttonStyle(.glass)
                .help("Visão do mural (\(zoomPercent)%)")

                Button("Adicionar arquivos", systemImage: "plus", action: onAdd)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .help("Adicionar arquivos (⌘O) — ou cole com ⌘V")
            }
        }
    }
}

#Preview {
    CanvasControls(zoomPercent: 100, onFit: {}, onActualSize: {}, onZoomIn: {}, onZoomOut: {}, onAdd: {})
        .padding(40)
        .background(Theme.canvas)
}
