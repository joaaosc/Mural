import AVFoundation
import Foundation
import Testing

@testable import Mural

@Suite("Prévia de vídeo ao passar o ponteiro")
@MainActor
struct HoverVideoPreviewTests {
    private let url = URL(fileURLWithPath: "/tmp/video-de-teste.mov")

    /// Controlador com espera curta e um tocador vazio, que conta quantos foram criados.
    private func makeController(delay: Duration = .milliseconds(40)) -> (HoverVideoPreviewController, Counter) {
        let counter = Counter()
        let controller = HoverVideoPreviewController(delay: delay) { _ in
            counter.value += 1
            return .init(player: AVQueuePlayer(), looper: nil)
        }
        return (controller, counter)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test("Começa a esperar ao entrar e só toca depois da espera")
    func playsOnlyAfterTheDelay() async {
        let (controller, counter) = makeController(delay: .milliseconds(150))

        controller.pointerEntered(url)

        #expect(controller.phase == .waiting)
        #expect(controller.player == nil)
        #expect(counter.value == 0)
        await waitUntil { controller.phase == .playing }
        #expect(controller.phase == .playing)
        #expect(controller.player != nil)
        #expect(counter.value == 1)
        controller.stop()
    }

    @Test("Sair antes do fim da espera não toca nada")
    func leavingBeforeTheDelayNeverPlays() async {
        let (controller, counter) = makeController(delay: .milliseconds(60))

        controller.pointerEntered(url)
        controller.stop()
        try? await Task.sleep(for: .milliseconds(200))

        #expect(controller.phase == .idle)
        #expect(controller.player == nil)
        #expect(counter.value == 0)
    }

    @Test("Parar solta o tocador e volta ao início")
    func stopReleasesThePlayer() async {
        let (controller, _) = makeController()
        controller.pointerEntered(url)
        await waitUntil { controller.phase == .playing }

        controller.stop()

        #expect(controller.phase == .idle)
        #expect(controller.player == nil)
    }

    @Test("Entrar de novo enquanto espera ou toca não cria outro tocador")
    func enteringAgainDoesNotStartASecondPlayer() async {
        let (controller, counter) = makeController()

        controller.pointerEntered(url)
        controller.pointerEntered(url)
        await waitUntil { controller.phase == .playing }
        controller.pointerEntered(url)
        try? await Task.sleep(for: .milliseconds(100))

        #expect(counter.value == 1)
        controller.stop()
    }

    @Test("Depois de parar, uma nova entrada toca de novo")
    func canPlayAgainAfterStopping() async {
        let (controller, counter) = makeController()
        controller.pointerEntered(url)
        await waitUntil { controller.phase == .playing }
        controller.stop()

        controller.pointerEntered(url)
        await waitUntil { controller.phase == .playing }

        #expect(counter.value == 2)
        controller.stop()
    }

    @Test("O tocador padrão é mudo, repete o vídeo e não segura a tela acesa")
    func silentLoopIsMutedAndLoops() {
        let playback = HoverVideoPreviewController.silentLoop(for: url)

        #expect(playback.player.isMuted)
        #expect(!playback.player.preventsDisplaySleepDuringVideoPlayback)
        #expect(playback.looper != nil)
        playback.looper?.disableLooping()
    }
}

private final class Counter {
    var value = 0
}
