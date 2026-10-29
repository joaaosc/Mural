import CoreGraphics
import Foundation
import MuralKit
import Testing

@testable import Mural

@Suite("Tocando agora")
@MainActor
struct MusicNowPlayingTests {
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
            MusicSnapshot(kind: .album, catalogID: "300", title: "Álbum C"),
            MusicSnapshot(kind: .station, catalogID: "400", title: "Estação D"),
        ]
    ) async throws -> Rig {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralMusicNowPlaying-\(UUID().uuidString)", isDirectory: true)
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
        return Rig(
            directory: directory, model: model, boardID: session.boardID, ids: ids, fake: fake,
            playback: MusicPlayback(provider: fake))
    }

    private func cleanup(_ rig: Rig) { try? FileManager.default.removeItem(at: rig.directory) }

    @Test("Guarda de onde vem a música: mural, rota, nomes e cartão")
    func recordsSource() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        let route = BoardRoute.saved(rig.boardID)

        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID, route: route, boardTitle: "Meu mural")

        let source = try #require(rig.playback.source)
        #expect(source.itemID == rig.ids[0])
        #expect(source.boardID == rig.boardID)
        #expect(source.route == route)
        #expect(source.boardTitle == "Meu mural")
        #expect(source.cardTitle == "Álbum A")
        #expect(source.music.title == "Álbum A")
        #expect(rig.playback.nowPlaying?.title == "Faixa 1")
    }

    @Test("Pausa e retoma sem o modelo do mural")
    func pauseAndResumeWithoutModel() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)

        await rig.playback.pauseOrResume()
        #expect(rig.fake.pauseCount == 1)
        #expect(rig.playback.phase(of: rig.ids[0]) == .paused)

        await rig.playback.pauseOrResume()
        #expect(rig.fake.resumeCount == 1)
        #expect(rig.playback.phase(of: rig.ids[0]) == .playing)
    }

    @Test("Próxima e anterior passam pelo tocador: Faixa 1, 2, 1")
    func skipsThroughProvider() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)
        #expect(rig.playback.nowPlaying?.title == "Faixa 1")

        await rig.playback.skipToNext()
        #expect(rig.fake.skipNextCount == 1)
        #expect(rig.playback.nowPlaying?.title == "Faixa 2")

        await rig.playback.skipToPrevious()
        #expect(rig.fake.skipPreviousCount == 1)
        #expect(rig.playback.nowPlaying?.title == "Faixa 1")
        #expect(rig.playback.canSkipBackward)
    }

    @Test("Erro ao pular mantém a fonte e o estado")
    func skipErrorKeepsState() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)
        rig.fake.skipError = .failed

        await rig.playback.skipToNext()

        #expect(rig.playback.source?.itemID == rig.ids[0])
        #expect(rig.playback.phase(of: rig.ids[0]) == .playing)
        #expect(rig.playback.nowPlaying?.title == "Faixa 1")
    }

    @Test("Estação não volta")
    func stationCannotGoBack() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        await rig.playback.toggle(rig.ids[2], in: rig.model, boardID: rig.boardID)

        #expect(rig.playback.canSkipBackward == false)
        await rig.playback.skipToPrevious()
        #expect(rig.fake.skipPreviousCount == 0)
        #expect(rig.playback.nowPlaying?.duration == nil)
    }

    @Test("stopCurrent para o tocador e limpa a fonte")
    func stopCurrentClearsSource() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)

        rig.playback.stopCurrent()

        #expect(rig.fake.stopCount == 1)
        #expect(rig.playback.source == nil)
        #expect(rig.playback.phase(of: rig.ids[0]) == .idle)
        #expect(rig.playback.nowPlaying == nil)
    }

    @Test("Parar durante o carregamento impede que a música comece depois")
    func stopDuringLoadingPreventsStart() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        rig.fake.playDelay = .milliseconds(200)
        let id = rig.ids[0]

        let task = Task { await rig.playback.toggle(id, in: rig.model, boardID: rig.boardID) }
        while !rig.playback.isLoading { await Task.yield() }
        #expect(rig.playback.phase(of: id) == .loading)
        rig.playback.stopCurrent()
        await task.value

        #expect(rig.playback.source == nil)
        #expect(rig.fake.status == .stopped)
        #expect(rig.playback.isLoading == false)
    }

    @Test("O fim da fila limpa a fonte")
    func queueEndClearsSource() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)

        rig.fake.finishQueue()

        #expect(rig.playback.source == nil)
        #expect(rig.playback.phase(of: rig.ids[0]) == .idle)
        #expect(rig.playback.nowPlaying == nil)
    }

    @Test("Pular além da última faixa termina a fila")
    func skippingPastTheLastEntryEnds() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)

        await rig.playback.skipToNext()
        await rig.playback.skipToNext()
        await rig.playback.skipToNext()

        #expect(rig.playback.source == nil)
    }

    @Test("O fim da fila do item anterior não limpa o cartão que está carregando")
    func previousQueueEndDoesNotClearLoadingCard() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)
        rig.fake.playDelay = .milliseconds(200)

        let task = Task { await rig.playback.toggle(rig.ids[1], in: rig.model, boardID: rig.boardID) }
        while !rig.playback.isLoading { await Task.yield() }
        rig.fake.finishQueue()
        #expect(rig.playback.source?.itemID == rig.ids[1])
        await task.value

        #expect(rig.playback.source?.itemID == rig.ids[1])
        #expect(rig.playback.phase(of: rig.ids[1]) == .playing)
    }

    @Test("moveSource só vale para o mural da fonte")
    func moveSourceOnlyForMatchingBoard() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        await rig.playback.toggle(
            rig.ids[0], in: rig.model, boardID: rig.boardID, route: .welcomeDraft(rig.boardID), boardTitle: "Rascunho")
        let other = BoardID(rawValue: UUID())

        rig.playback.moveSource(from: other, to: .saved(other), title: "Outro")
        #expect(rig.playback.source?.boardID == rig.boardID)
        #expect(rig.playback.source?.boardTitle == "Rascunho")

        let saved = BoardID(rawValue: UUID())
        rig.playback.moveSource(from: rig.boardID, to: .saved(saved), title: "Salvo")
        #expect(rig.playback.source?.boardID == saved)
        #expect(rig.playback.source?.route == .saved(saved))
        #expect(rig.playback.source?.boardTitle == "Salvo")
    }

    @Test("renameSource muda o nome só do mural da fonte")
    func renameSourceUpdatesTitle() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID, boardTitle: "Antes")

        rig.playback.renameSource(boardID: BoardID(rawValue: UUID()), to: "Errado")
        #expect(rig.playback.source?.boardTitle == "Antes")

        rig.playback.renameSource(boardID: rig.boardID, to: "Depois")
        #expect(rig.playback.source?.boardTitle == "Depois")
    }
}
