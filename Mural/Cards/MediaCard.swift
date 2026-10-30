import AppKit
import MuralKit
import SwiftUI

/// Foto, vídeo ou PDF: a miniatura recortada com cantos arredondados. Com `previewVideoURL`, o ponteiro parado sobre
/// o cartão toca esse vídeo, mudo e em laço, por cima da miniatura (só onde `hoverVideoPreviewEnabled` está ligado).
struct MediaCard: View {
    let url: URL?
    let kind: ItemKind
    /// Vídeo da prévia. Hoje é o próprio arquivo do cartão de vídeo; uma foto com vídeo junto (Live Photo) passaria o dela.
    var previewVideoURL: URL? = nil

    @Environment(\.hoverVideoPreviewEnabled) private var previewEnabled
    @State private var preview = HoverVideoPreviewController()
    @State private var isPreviewReady = false

    private var isShowingPreview: Bool { preview.player != nil && isPreviewReady }

    var body: some View {
        // O Color.clear define o tamanho; a miniatura preenche e é recortada.
        Color.clear
            .overlay { ThumbnailView(url: url, kind: kind, contentMode: .fill) }
            .overlay {
                if kind == .video, !isShowingPreview {
                    Image(systemName: "play.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                }
            }
            .overlay {
                if let player = preview.player {
                    HoverVideoSurface(player: player) { isPreviewReady = $0 }
                        .opacity(isPreviewReady ? 1 : 0)
                        .animation(.easeOut(duration: 0.15), value: isPreviewReady)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("hover-video-preview")
                        .accessibilityValue(isPreviewReady ? "pronta" : "carregando")
                }
            }
            .background(kind == .pdf ? Theme.paper : .clear)
            .clipShape(.rect(cornerRadius: kind == .pdf ? Theme.cardCorner : Theme.mediaCorner))
            // O recorte esconde a sobra da miniatura que preenche, mas não a tira do clique, do ponteiro nem da acessibilidade:
            // sem esta forma, uma foto deitada num cartão em pé recebe cliques e arrastos fora do cartão, e o quadro dele na
            // acessibilidade fica do tamanho da foto inteira.
            .contentShape(.rect(cornerRadius: kind == .pdf ? Theme.cardCorner : Theme.mediaCorner))
            .cardShadow()
            // A folha de trás da foto, como a da pasta. Fica no fundo, depois da forma de toque: não aumenta a área
            // clicável nem o quadro da acessibilidade.
            .background {
                if kind == .image {
                    RoundedRectangle(cornerRadius: Theme.mediaCorner)
                        .fill(Theme.paperBack)
                        .offset(x: 6)
                        .cardShadow()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onHover { inside in
                if inside, previewEnabled, let previewVideoURL {
                    preview.pointerEntered(previewVideoURL)
                } else {
                    stopPreview()
                }
            }
            .onChange(of: previewEnabled) { _, enabled in if !enabled { stopPreview() } }
            .onChange(of: previewVideoURL) { stopPreview() }
            .onDisappear { stopPreview() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                stopPreview()
            }
    }

    private func stopPreview() {
        preview.stop()
        isPreviewReady = false
    }
}

#if DEBUG
#Preview("Foto com folha atrás", traits: .fixedLayout(width: 320, height: 260)) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("MuralMediaCard-preview.png")
    let colors = [Color(red: 0.93, green: 0.42, blue: 0.33), Color(red: 0.45, green: 0.22, blue: 0.16)]
    if let data = PreviewImages.png(colors: colors, size: CGSize(width: 600, height: 450)) {
        try? data.write(to: url)
    }
    return HStack(spacing: 30) {
        MediaCard(url: url, kind: .image)
            .frame(width: 140, height: 105)
        MediaCard(url: url, kind: .image)
            .frame(width: 100, height: 130)
    }
    .padding(30)
}
#endif
