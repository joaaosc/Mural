import SwiftUI

/// Controle do canto inferior direito do mural: o menu de visão (zoom). Criar conteúdo
/// fica na barra do centro (`CreationBar`); os atalhos de zoom, no menu Visualizar.
struct CanvasControls: View {
    let zoom: CanvasZoomController

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

            }
        }
    }
}

#Preview {
    CanvasControls(zoom: CanvasZoomController())
        .padding(40)
        .background { PreviewBackdrop() }
}
