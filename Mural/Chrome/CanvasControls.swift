import SwiftUI

/// Controles do canto inferior direito do mural: menu de visão (zoom) e adicionar.
/// Os atalhos de zoom ficam no menu Visualizar.
struct CanvasControls: View {
    let zoom: CanvasZoomController
    var onAdd: () -> Void

    private var zoomPercent: Int { Int((zoom.displayedZoom * 100).rounded()) }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Menu {
                    Button("Aproximar", action: zoom.zoomIn)
                    Button("Afastar", action: zoom.zoomOut)
                    Divider()
                    Button("Tamanho real", action: zoom.actualSize)
                    Button("Ajustar à janela", action: zoom.fitToWindow)
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
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .help("Adicionar arquivos (⇧⌘I) — ou cole com ⌘V")
            }
        }
    }
}

#Preview {
    CanvasControls(zoom: CanvasZoomController(), onAdd: {})
        .padding(40)
        .background(Theme.canvas)
}
