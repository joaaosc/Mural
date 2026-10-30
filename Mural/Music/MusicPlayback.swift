import Foundation
import MuralKit
import OSLog
import Observation

/// Pedido de mostrar a oferta de assinatura do Apple Music.
struct MusicOfferRequest: Identifiable, Equatable {
    let id = UUID()
    let catalogID: String?
    /// Mural que pediu: só a janela dele mostra a oferta.
    let boardID: BoardID
}

/// Como um cartão de música aparece em relação ao tocador.
enum MusicCardPhase: Equatable {
    case idle, loading, playing, paused
}

/// De onde vem a música que toca: o cartão, o mural e o que mostrar deles sem abrir o mural.
struct MusicPlaybackSource: Equatable, Sendable {
    let itemID: UUID
    var boardID: BoardID
    var route: BoardRoute
    var boardTitle: String
    var cardTitle: String
    var music: MusicSnapshot
    /// A nota que guarda a música, quando ela toca de um cartão embutido (`itemID` é então o id do cartão embutido, que não é
    /// um cartão do mural); `nil` para o cartão de música solto.
    var ownerItemID: UUID?
}

/// Uma música embutida numa nota, para tocar sem ser um cartão do mural.
struct EmbeddedMusic: Equatable, Sendable {
    /// O id do cartão embutido (o `UUID` de `mural-card:<UUID>`).
    let cardID: UUID
    /// A nota que o guarda.
    let ownerItemID: UUID
    let music: MusicSnapshot
    let title: String
}

/// Coordena o que toca: um cartão por vez, para o app inteiro.
@MainActor
@Observable
final class MusicPlayback {
    static let shared = MusicPlayback(provider: MusicCenter.shared)

    private(set) var source: MusicPlaybackSource?
    private(set) var isLoading = false
    var offer: MusicOfferRequest?

    @ObservationIgnored private let provider: any MusicProviding
    /// Distingue cargas sobrepostas: só a mais recente desliga `isLoading`.
    @ObservationIgnored private var loadGeneration = 0
    /// Espera antes de dar a fila por encerrada: o MusicKit pode avisar uma parada passageira ao trocar a fila.
    @ObservationIgnored private let endConfirmationDelay: Duration
    @ObservationIgnored private var endConfirmation: Task<Void, Never>?
    private static let logger = Logger(subsystem: "com.joaocosta.Mural", category: "Música")

    init(provider: any MusicProviding, endConfirmationDelay: Duration = .milliseconds(400)) {
        self.provider = provider
        self.endConfirmationDelay = endConfirmationDelay
        provider.onPlaybackEnded = { [weak self] in self?.playbackEnded() }
    }

    var currentItemID: UUID? { source?.itemID }
    var currentBoardID: BoardID? { source?.boardID }

    /// A entrada que o tocador está tocando agora.
    var nowPlaying: MusicNowPlaying? { provider.nowPlaying }
    var playbackTime: TimeInterval { provider.playbackTime }
    var shuffle: MusicShuffle? { provider.shuffle }
    var repeatMode: MusicRepeat? { provider.repeatMode }
    /// Dá para arrastar a posição: a duração é conhecida e nada está carregando.
    var canSeek: Bool { !isLoading && (nowPlaying?.duration ?? 0) > 0 }
    /// Estação não tem aleatório; fora isso, depende de o tocador oferecê-lo.
    var canShuffle: Bool {
        guard let source, source.music.kind != .station, !isLoading else { return false }
        return provider.shuffle != nil
    }
    var canRepeat: Bool { source != nil && !isLoading && provider.repeatMode != nil }
    /// Estação não volta; sem música, nada a fazer.
    var canSkipBackward: Bool { source.map { $0.music.kind != .station } ?? false }

    /// Só o cartão atual tem fase diferente de `.idle`.
    func phase(of itemID: UUID) -> MusicCardPhase {
        guard itemID == currentItemID else { return .idle }
        if isLoading { return .loading }
        switch provider.status {
        case .playing: return .playing
        case .paused: return .paused
        case .stopped: return .idle
        }
    }

    /// Cartão atual tocando: pausa; pausado: retoma; qualquer outro: começa.
    ///
    /// Com `embedded`, `itemID` é o id do cartão embutido e a música vem dele, não do mural.
    func toggle(
        _ itemID: UUID, in model: BoardModel, boardID: BoardID, route: BoardRoute? = nil, boardTitle: String? = nil,
        embedded: EmbeddedMusic? = nil
    ) async {
        // Segundo clique enquanto carrega: espera o primeiro, em vez de tocar duas vezes.
        if itemID == currentItemID, isLoading { return }
        if itemID == currentItemID {
            switch provider.status {
            case .playing:
                provider.pause()
                return
            case .paused:
                do { try await provider.resume() } catch {
                    model.lastError = "Não foi possível retomar a música."
                }
                return
            case .stopped:
                break
            }
        }
        await start(
            itemID, startingAt: nil, in: model, boardID: boardID, route: route, boardTitle: boardTitle, embedded: embedded)
    }

    func play(
        _ itemID: UUID, startingAt trackID: String?, in model: BoardModel, boardID: BoardID,
        route: BoardRoute? = nil, boardTitle: String? = nil
    ) async {
        await start(itemID, startingAt: trackID, in: model, boardID: boardID, route: route, boardTitle: boardTitle)
    }

    /// Pausa ou retoma a música atual, sem precisar do mural de origem.
    func pauseOrResume() async {
        guard source != nil, !isLoading else { return }
        switch provider.status {
        case .playing: provider.pause()
        case .paused:
            do { try await provider.resume() } catch {
                Self.logger.error("Não foi possível retomar a música.")
            }
        case .stopped: break
        }
    }

    func skipToNext() async {
        guard source != nil, !isLoading else { return }
        do { try await provider.skipToNext() } catch {
            Self.logger.error("Não foi possível pular para a próxima faixa.")
        }
    }

    func skipToPrevious() async {
        guard canSkipBackward, !isLoading else { return }
        do { try await provider.skipToPrevious() } catch {
            Self.logger.error("Não foi possível voltar para a faixa anterior.")
        }
    }

    /// Liga ou desliga o aleatório.
    func toggleShuffle() {
        guard canShuffle, let current = provider.shuffle else { return }
        provider.setShuffle(current.toggled)
    }

    /// Passa a repetição para a próxima: nenhuma, tudo, uma.
    func cycleRepeat() {
        guard canRepeat, let current = provider.repeatMode else { return }
        provider.setRepeat(current.next)
    }

    /// Leva a reprodução para a posição, presa entre 0 e a duração.
    func seek(to time: TimeInterval) {
        guard canSeek, time.isFinite, let duration = nowPlaying?.duration else { return }
        provider.seek(to: min(max(time, 0), duration))
    }

    /// Para o que estiver tocando (ou carregando), de qualquer mural.
    func stopCurrent() {
        guard source != nil else { return }
        provider.stop()
        clearCurrent()
    }

    /// O mural de origem virou outro (rascunho promovido): a fonte aponta para o mural salvo.
    func moveSource(from boardID: BoardID, to route: BoardRoute, title: String) {
        guard source?.boardID == boardID else { return }
        switch route {
        case .saved(let id), .welcomeDraft(let id): source?.boardID = id
        case .library: return
        }
        source?.route = route
        source?.boardTitle = title
    }

    func renameSource(boardID: BoardID, to title: String) {
        guard source?.boardID == boardID else { return }
        source?.boardTitle = title
    }

    /// Situação da permissão de acesso ao Apple Music.
    var access: MusicAccess { provider.access }

    func requestAccess() async -> MusicAccess {
        await provider.requestAccess()
    }

    func tracks(for snapshot: MusicSnapshot) async throws -> [MusicTrackRow] {
        try await provider.tracks(for: snapshot)
    }

    func catalogArtwork(for snapshot: MusicSnapshot) async -> MusicCatalogArtwork? {
        await provider.catalogArtwork(for: snapshot)
    }

    func stop(itemID: UUID) {
        guard currentItemID == itemID else { return }
        provider.stop()
        clearCurrent()
    }

    func stop(boardID: BoardID) {
        guard currentBoardID == boardID else { return }
        provider.stop()
        clearCurrent()
    }

    /// Para quando o cartão atual deste mural não existe mais (apagado, ou junto com uma pasta).
    func stopIfMissing(in model: BoardModel, boardID: BoardID) {
        guard currentBoardID == boardID, let owner = source?.ownerItemID ?? currentItemID, model.item(id: owner) == nil
        else { return }
        provider.stop()
        clearCurrent()
    }

    private func clearCurrent() {
        endConfirmation?.cancel()
        endConfirmation = nil
        source = nil
    }

    /// A fila acabou ou o sistema parou o tocador. Durante uma carga o aviso é da música anterior.
    /// Esconder o tocador só depois de confirmar que o áudio parou de fato.
    private func playbackEnded() {
        guard !isLoading else { return }
        endConfirmation?.cancel()
        guard endConfirmationDelay > .zero else {
            confirmEnd()
            return
        }
        let delay = endConfirmationDelay
        endConfirmation = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.confirmEnd()
        }
    }

    private func confirmEnd() {
        endConfirmation = nil
        guard !isLoading, provider.status == .stopped, provider.nowPlaying == nil else { return }
        clearCurrent()
    }

    private func start(
        _ itemID: UUID, startingAt trackID: String?, in model: BoardModel, boardID: BoardID,
        route: BoardRoute?, boardTitle: String?, embedded: EmbeddedMusic? = nil
    ) async {
        guard let music = embedded?.music ?? model.item(id: itemID)?.music else { return }

        var access = provider.access
        if access == .notDetermined { access = await provider.requestAccess() }
        guard access == .granted else {
            model.lastError =
                "O acesso ao Apple Music está desligado. Ligue em Ajustes do Sistema › Privacidade e Segurança › Mídia e Apple Music."
            return
        }

        switch await provider.eligibility() {
        case .canPlay: break
        case .canSubscribe:
            offer = MusicOfferRequest(catalogID: music.catalogID, boardID: boardID)
            return
        case .cannotPlay:
            model.lastError = "Esta conta não pode tocar o Apple Music."
            return
        }

        if let currentItemID, currentItemID != itemID { provider.stop() }
        loadGeneration += 1
        let generation = loadGeneration
        endConfirmation?.cancel()
        endConfirmation = nil
        isLoading = true
        let cardTitle = embedded?.title ?? model.item(id: itemID)?.title ?? ""
        source = MusicPlaybackSource(
            itemID: itemID, boardID: boardID, route: route ?? .saved(boardID), boardTitle: boardTitle ?? "Mural",
            cardTitle: cardTitle.isEmpty ? music.title : cardTitle, music: music, ownerItemID: embedded?.ownerItemID)
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let resolved = try await provider.play(music, startingAt: trackID)
            // Parar (ou apagar o mural) durante o carregamento não pode deixar a música começar depois.
            guard source?.itemID == itemID else {
                if source == nil { provider.stop() }
                return
            }
            if resolved != music {
                // A música embutida não é um cartão do mural: só o tocador guarda o estado resolvido.
                if embedded == nil { model.updateMusic(itemID, with: resolved) }
                source?.music = resolved
            }
        } catch {
            if source?.itemID == itemID { clearCurrent() }
            model.lastError = Self.message(for: error, music: music)
        }
    }

    private static func message(for error: any Error, music: MusicSnapshot) -> String {
        switch error as? MusicPlaybackError {
        case .notFound: "Não foi possível achar “\(music.title)” no Apple Music."
        case .ambiguousPlaylist:
            "Há mais de uma playlist chamada “\(music.libraryPlaylistName ?? music.title)” na biblioteca."
        case .notPlayable: "Este item não tem como tocar pelo Mural. Abra no Música."
        case .failed, .none:
            "Não foi possível tocar “\(music.title)”. Confira a conexão e a conta do Apple Music."
        }
    }
}
