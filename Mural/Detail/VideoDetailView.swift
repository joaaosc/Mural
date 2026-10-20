import AVKit
import SwiftUI

/// Vídeo com os controles padrão do sistema. Pausa ao sair da tela.
struct VideoDetailView: View {
    let url: URL?
    let title: String

    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if url == nil {
                ContentUnavailableView("Vídeo não encontrado", systemImage: "exclamationmark.triangle")
            } else if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView()
            }
        }
        .clipShape(.rect(cornerRadius: Theme.mediaCorner))
        .padding(.horizontal, 110)
        .padding(.top, 70)
        .padding(.bottom, 80)
        .accessibilityLabel("Vídeo \(title)")
        .task(id: url) {
            guard let url else { return }
            player = AVPlayer(url: url)
        }
        .onDisappear { player?.pause() }
    }
}
