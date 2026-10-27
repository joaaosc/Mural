import AVFoundation
import AppKit
import SwiftUI

extension EnvironmentValues {
    /// Se o cartão de mídia pode tocar a prévia do vídeo quando o ponteiro fica parado sobre ele. Só o `CardButton`
    /// liga: no mural e dentro da pasta, com o seletor de ⌘ fechado e sem Reduzir Movimento. A prévia de pasta
    /// (ao passar o ponteiro) e as capas ficam no padrão, desligado.
    @Entry var hoverVideoPreviewEnabled = false
}

/// Prévia de um vídeo dentro do cartão: com o ponteiro parado, toca sem som e em laço; ao sair, para e solta o
/// vídeo. Um por cartão, e só existe tocador enquanto a prévia toca.
@MainActor
@Observable
final class HoverVideoPreviewController {
    enum Phase: Equatable {
        case idle
        /// O ponteiro entrou e a espera ainda não acabou.
        case waiting
        case playing
    }

    /// O tocador e o laço que o mantém repetindo. Entra por parâmetro para os testes não precisarem de vídeo.
    struct Playback {
        let player: AVQueuePlayer
        let looper: AVPlayerLooper?
    }

    static let defaultDelay: Duration = .milliseconds(500)

    private(set) var phase: Phase = .idle
    private(set) var player: AVQueuePlayer?

    @ObservationIgnored private var looper: AVPlayerLooper?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private let makePlayback: @MainActor (URL) -> Playback

    init(delay: Duration = defaultDelay, makePlayback: @escaping @MainActor (URL) -> Playback = silentLoop) {
        self.delay = delay
        self.makePlayback = makePlayback
    }

    /// Tocador mudo, em laço, que não segura a tela acesa.
    static func silentLoop(for url: URL) -> Playback {
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        return Playback(player: player, looper: looper)
    }

    /// O ponteiro entrou no cartão: começa a esperar. Se já espera ou toca, não faz nada.
    func pointerEntered(_ url: URL) {
        guard phase == .idle else { return }
        phase = .waiting
        startTask = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.start(url)
        }
    }

    /// Cancela a espera ou para o vídeo e solta o tocador. Pode ser chamado a qualquer hora.
    func stop() {
        startTask?.cancel()
        startTask = nil
        looper?.disableLooping()
        looper = nil
        player?.pause()
        player?.removeAllItems()
        player = nil
        phase = .idle
    }

    private func start(_ url: URL) {
        guard phase == .waiting else { return }
        let playback = makePlayback(url)
        looper = playback.looper
        player = playback.player
        phase = .playing
        playback.player.play()
    }
}

/// Camada do vídeo, preenchendo o cartão como a miniatura. Só aparece (por `onReadyForDisplay`) depois que o primeiro
/// quadro está pronto, para não piscar preto sobre a miniatura.
struct HoverVideoSurface: NSViewRepresentable {
    let player: AVPlayer
    let onReadyForDisplay: (Bool) -> Void

    func makeNSView(context: Context) -> HoverVideoLayerView {
        let view = HoverVideoLayerView()
        view.playerLayer.player = player
        view.onReadyForDisplay = onReadyForDisplay
        return view
    }

    func updateNSView(_ view: HoverVideoLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
        view.onReadyForDisplay = onReadyForDisplay
    }

    static func dismantleNSView(_ view: HoverVideoLayerView, coordinator: ()) {
        view.playerLayer.player = nil
    }
}

final class HoverVideoLayerView: NSView {
    let playerLayer = AVPlayerLayer()
    var onReadyForDisplay: ((Bool) -> Void)?
    private var readiness: NSKeyValueObservation?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        playerLayer.videoGravity = .resizeAspectFill
        layer = playerLayer
        wantsLayer = true
        readiness = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            let ready = layer.isReadyForDisplay
            Task { @MainActor in self?.onReadyForDisplay?(ready) }
        }
    }

    required init?(coder: NSCoder) { nil }

    /// O clique passa direto para o cartão.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
