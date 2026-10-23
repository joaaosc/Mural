import Foundation
import MuralKit
import Observation

/// Faixas de um álbum ou playlist na página do cartão, com o que mostrar enquanto não dá para listar.
@MainActor
@Observable
final class MusicTrackList {
    enum State: Equatable {
        case idle
        /// Faixa ou estação: não há lista.
        case hidden
        case needsAccess
        case denied
        case loading
        case loaded([MusicTrackRow])
        case unavailable
    }

    private(set) var state: State = .idle

    /// Número do pedido mais novo; resposta de um pedido antigo é descartada.
    @ObservationIgnored private var generation = 0

    func load(_ music: MusicSnapshot, playback: MusicPlayback) async {
        generation += 1
        let mine = generation
        guard music.kind == .album || music.kind == .playlist else {
            state = .hidden
            return
        }
        switch playback.access {
        case .notDetermined:
            state = .needsAccess
        case .denied, .restricted:
            state = .denied
        case .granted:
            state = .loading
            let result: State
            do {
                let rows = try await playback.tracks(for: music)
                result = rows.isEmpty ? .unavailable : .loaded(rows)
            } catch {
                result = .unavailable
            }
            if mine == generation { state = result }
        }
    }

    /// Pede a permissão (a pedido do botão) e carrega a lista.
    func allowAccess(_ music: MusicSnapshot, playback: MusicPlayback) async {
        _ = await playback.requestAccess()
        await load(music, playback: playback)
    }
}
