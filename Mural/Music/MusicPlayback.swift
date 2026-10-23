import Foundation
import MuralKit
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

/// Coordena o que toca: um cartão por vez, para o app inteiro.
@MainActor
@Observable
final class MusicPlayback {
    static let shared = MusicPlayback(provider: MusicCenter.shared)

    private(set) var currentItemID: UUID?
    private(set) var currentBoardID: BoardID?
    private(set) var isLoading = false
    var offer: MusicOfferRequest?

    @ObservationIgnored private let provider: any MusicProviding

    init(provider: any MusicProviding) {
        self.provider = provider
    }

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
    func toggle(_ itemID: UUID, in model: BoardModel, boardID: BoardID) async {
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
        await start(itemID, startingAt: nil, in: model, boardID: boardID)
    }

    func play(_ itemID: UUID, startingAt trackID: String?, in model: BoardModel, boardID: BoardID) async {
        await start(itemID, startingAt: trackID, in: model, boardID: boardID)
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
        guard currentBoardID == boardID, let currentItemID, model.item(id: currentItemID) == nil else { return }
        provider.stop()
        clearCurrent()
    }

    private func clearCurrent() {
        currentItemID = nil
        currentBoardID = nil
    }

    private func start(_ itemID: UUID, startingAt trackID: String?, in model: BoardModel, boardID: BoardID) async {
        guard let music = model.item(id: itemID)?.music else { return }

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
        isLoading = true
        currentItemID = itemID
        currentBoardID = boardID
        defer { isLoading = false }
        do {
            let resolved = try await provider.play(music, startingAt: trackID)
            if resolved != music { model.updateMusic(itemID, with: resolved) }
        } catch {
            currentItemID = nil
            currentBoardID = nil
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
