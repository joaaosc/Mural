import CoreGraphics
import Foundation
import MuralKit
import Testing

@testable import Mural

@Suite("Reprodução de música")
@MainActor
struct MusicPlaybackTests {
    private struct Rig {
        let directory: URL
        let model: BoardModel
        let boardID: BoardID
        let ids: [UUID]
        let fake: FakeMusic
        let playback: MusicPlayback
    }

    private func makeRig(
        snapshots: [MusicSnapshot] = [
            MusicSnapshot(kind: .album, catalogID: "100", title: "Álbum A"),
            MusicSnapshot(kind: .song, catalogID: "200", title: "Faixa B"),
        ],
        configure: (FakeMusic) -> Void = { _ in }
    ) async throws -> Rig {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralMusicPlayback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Música")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        await session.load()
        let metrics = CanvasScrollMetrics(
            contentOffset: .zero, containerSize: CGSize(width: 900, height: 700), contentSize: CGSize(width: 3_400, height: 2_800))
        for _ in 0..<3 where session.restorationPhase != .ready {
            session.restoreCanvas(boardID: session.boardID, generation: session.presentationGeneration, metrics: metrics)
        }
        try #require(session.restorationPhase == .ready)
        let model = try #require(session.model)
        let ids = session.importMusic(snapshots.map { MusicDraft(snapshot: $0) }, into: nil, artwork: nil, animation: nil)
        try #require(ids.count == snapshots.count)
        let fake = FakeMusic(arguments: [])
        configure(fake)
        return Rig(
            directory: directory, model: model, boardID: session.boardID, ids: ids, fake: fake,
            playback: MusicPlayback(provider: fake))
    }

    private func cleanup(_ rig: Rig) { try? FileManager.default.removeItem(at: rig.directory) }

    @Test("Toca, pausa e retoma o mesmo cartão")
    func playPauseResume() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        let id = rig.ids[0]

        #expect(rig.playback.phase(of: id) == .idle)
        await rig.playback.toggle(id, in: rig.model, boardID: rig.boardID)
        #expect(rig.fake.played.count == 1)
        #expect(rig.playback.currentItemID == id)
        #expect(rig.playback.currentBoardID == rig.boardID)
        #expect(rig.playback.phase(of: id) == .playing)

        await rig.playback.toggle(id, in: rig.model, boardID: rig.boardID)
        #expect(rig.fake.pauseCount == 1)
        #expect(rig.playback.phase(of: id) == .paused)

        await rig.playback.toggle(id, in: rig.model, boardID: rig.boardID)
        #expect(rig.fake.resumeCount == 1)
        #expect(rig.fake.played.count == 1)
        #expect(rig.playback.phase(of: id) == .playing)
        #expect(rig.model.lastError == nil)
    }

    @Test("Outro cartão para o anterior e toca o novo")
    func otherCardStopsPrevious() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }

        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)
        await rig.playback.toggle(rig.ids[1], in: rig.model, boardID: rig.boardID)

        #expect(rig.fake.stopCount == 1)
        #expect(rig.fake.played.count == 2)
        #expect(rig.playback.currentItemID == rig.ids[1])
        #expect(rig.playback.phase(of: rig.ids[0]) == .idle)
        #expect(rig.playback.phase(of: rig.ids[1]) == .playing)
    }

    @Test("Repassa a faixa inicial")
    func startingAtIsForwarded() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }

        await rig.playback.play(rig.ids[0], startingAt: "faixa-2", in: rig.model, boardID: rig.boardID)

        #expect(rig.fake.played.first?.1 == "faixa-2")
    }

    @Test("Acesso negado avisa e não toca")
    func deniedAccess() async throws {
        let rig = try await makeRig { $0.access = .denied }
        defer { cleanup(rig) }

        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)

        #expect(rig.fake.played.isEmpty)
        #expect(rig.model.lastError?.hasPrefix("O acesso ao Apple Music está desligado.") == true)
        #expect(rig.playback.currentItemID == nil)
    }

    @Test("Acesso restrito também avisa")
    func restrictedAccess() async throws {
        let rig = try await makeRig { $0.access = .restricted }
        defer { cleanup(rig) }

        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)

        #expect(rig.fake.played.isEmpty)
        #expect(rig.model.lastError != nil)
    }

    @Test("Acesso ainda não decidido pede e toca")
    func notDeterminedAsksThenPlays() async throws {
        let rig = try await makeRig { $0.access = .notDetermined }
        defer { cleanup(rig) }

        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)

        #expect(rig.fake.requestAccessCount == 1)
        #expect(rig.fake.played.count == 1)
    }

    @Test("Pedido negado não toca")
    func notDeterminedThenDenied() async throws {
        let rig = try await makeRig {
            $0.access = .notDetermined
            $0.accessAfterRequest = .denied
        }
        defer { cleanup(rig) }

        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)

        #expect(rig.fake.requestAccessCount == 1)
        #expect(rig.fake.played.isEmpty)
        #expect(rig.model.lastError != nil)
    }

    @Test("Sem assinatura pede a oferta com o id do catálogo e não toca")
    func subscriptionOffer() async throws {
        let rig = try await makeRig { $0.eligibilityResult = .canSubscribe }
        defer { cleanup(rig) }

        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)

        #expect(rig.fake.played.isEmpty)
        #expect(rig.playback.offer?.catalogID == "100")
        #expect(rig.playback.offer?.boardID == rig.boardID)
        #expect(rig.playback.currentItemID == nil)
    }

    @Test("Conta que não pode tocar avisa")
    func cannotPlay() async throws {
        let rig = try await makeRig { $0.eligibilityResult = .cannotPlay }
        defer { cleanup(rig) }

        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)

        #expect(rig.fake.played.isEmpty)
        #expect(rig.model.lastError == "Esta conta não pode tocar o Apple Music.")
    }

    @Test("Playlist ambígua avisa com o nome e limpa o atual")
    func ambiguousPlaylist() async throws {
        let rig = try await makeRig(
            snapshots: [MusicSnapshot(kind: .playlist, libraryPlaylistName: "Treino", title: "Treino")]
        ) { $0.playError = .ambiguousPlaylist }
        defer { cleanup(rig) }

        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)

        #expect(rig.model.lastError == "Há mais de uma playlist chamada “Treino” na biblioteca.")
        #expect(rig.playback.currentItemID == nil)
        #expect(rig.playback.isLoading == false)
    }

    @Test("Demais erros têm mensagem própria")
    func otherErrors() async throws {
        let cases: [(MusicPlaybackError, String)] = [
            (.notFound, "Não foi possível achar “Álbum A” no Apple Music."),
            (.notPlayable, "Este item não tem como tocar pelo Mural. Abra no Música."),
            (.failed, "Não foi possível tocar “Álbum A”. Confira a conexão e a conta do Apple Music."),
        ]
        for (error, message) in cases {
            let rig = try await makeRig { $0.playError = error }
            defer { cleanup(rig) }
            await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)
            #expect(rig.model.lastError == message)
            #expect(rig.playback.currentItemID == nil)
        }
    }

    @Test("Playlist própria resolvida grava o libraryID no cartão")
    func resolvedLibraryIDIsSaved() async throws {
        let rig = try await makeRig(
            snapshots: [MusicSnapshot(kind: .playlist, libraryPlaylistName: "Treino", title: "Treino")]
        ) { $0.resolvedLibraryID = "p.ABC" }
        defer { cleanup(rig) }

        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)

        #expect(rig.model.item(id: rig.ids[0])?.music?.libraryID == "p.ABC")
    }

    @Test("stop(itemID:) só para o cartão atual")
    func stopByItem() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)

        rig.playback.stop(itemID: rig.ids[1])
        #expect(rig.fake.stopCount == 0)
        #expect(rig.playback.currentItemID == rig.ids[0])

        rig.playback.stop(itemID: rig.ids[0])
        #expect(rig.fake.stopCount == 1)
        #expect(rig.playback.currentItemID == nil)
        #expect(rig.playback.phase(of: rig.ids[0]) == .idle)
    }

    @Test("stop(boardID:) só para o mural atual")
    func stopByBoard() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)

        rig.playback.stop(boardID: BoardID(rawValue: UUID()))
        #expect(rig.fake.stopCount == 0)
        #expect(rig.playback.currentBoardID == rig.boardID)

        rig.playback.stop(boardID: rig.boardID)
        #expect(rig.fake.stopCount == 1)
        #expect(rig.playback.currentItemID == nil)
        #expect(rig.playback.currentBoardID == nil)
    }

    @Test("stopIfMissing para quando o cartão atual saiu do modelo e ignora o resto")
    func stopIfMissing() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)

        rig.playback.stopIfMissing(in: rig.model, boardID: rig.boardID)
        #expect(rig.fake.stopCount == 0)

        rig.model.delete(rig.ids[1])
        rig.playback.stopIfMissing(in: rig.model, boardID: rig.boardID)
        #expect(rig.fake.stopCount == 0)

        rig.model.delete(rig.ids[0])
        rig.playback.stopIfMissing(in: rig.model, boardID: BoardID(rawValue: UUID()))
        #expect(rig.fake.stopCount == 0)
        rig.playback.stopIfMissing(in: rig.model, boardID: rig.boardID)
        #expect(rig.fake.stopCount == 1)
        #expect(rig.playback.currentItemID == nil)
        #expect(rig.playback.currentBoardID == nil)
    }
}
