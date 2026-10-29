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
        endConfirmationDelay: Duration = .zero,
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
            playback: MusicPlayback(provider: fake, endConfirmationDelay: endConfirmationDelay))
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

    @Test("Aleatório liga e desliga pelo tocador")
    func togglesShuffle() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)
        #expect(rig.playback.shuffle == .off)

        rig.playback.toggleShuffle()
        #expect(rig.playback.shuffle == .songs)
        rig.playback.toggleShuffle()
        #expect(rig.playback.shuffle == .off)
        #expect(rig.fake.shuffleCalls == [.songs, .off])
    }

    @Test("Repetir passa por nenhuma, tudo, uma e volta")
    func cyclesRepeat() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)
        #expect(rig.playback.repeatMode == MusicRepeat.none)

        var seen: [MusicRepeat?] = []
        for _ in 0..<3 {
            rig.playback.cycleRepeat()
            seen.append(rig.playback.repeatMode)
        }
        #expect(seen == [.all, .one, MusicRepeat.none])
    }

    @Test("Estação não tem aleatório")
    func stationDisablesShuffle() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        await rig.playback.toggle(rig.ids[2], in: rig.model, boardID: rig.boardID)

        #expect(rig.playback.canShuffle == false)
        rig.playback.toggleShuffle()
        #expect(rig.fake.shuffleCalls.isEmpty)
    }

    @Test("Sem o modo no tocador, aleatório e repetição ficam desligados")
    func unavailableModesDisableControls() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        rig.fake.shuffle = nil
        rig.fake.repeatMode = nil
        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)

        #expect(rig.playback.canShuffle == false)
        #expect(rig.playback.canRepeat == false)
        rig.playback.cycleRepeat()
        #expect(rig.fake.repeatCalls.isEmpty)
    }

    @Test("Buscar vai ao tocador, preso entre 0 e a duração")
    func seekClampsAndForwards() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)
        #expect(rig.playback.canSeek)

        rig.playback.seek(to: 42)
        #expect(rig.playback.playbackTime == 42)
        rig.playback.seek(to: 9_999)
        #expect(rig.playback.playbackTime == 180)
        rig.playback.seek(to: -5)
        #expect(rig.playback.playbackTime == 0)
        #expect(rig.fake.seekCalls == [42, 180, 0])
    }

    @Test("Estação não tem duração: não dá para buscar")
    func stationCannotSeek() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        await rig.playback.toggle(rig.ids[2], in: rig.model, boardID: rig.boardID)

        #expect(rig.playback.canSeek == false)
        rig.playback.seek(to: 10)
        #expect(rig.fake.seekCalls.isEmpty)
    }

    @Test("Anterior com mais de 3 s volta ao início; até 3 s, à faixa anterior")
    func previousRestartsAfterThreeSeconds() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)
        await rig.playback.skipToNext()
        #expect(rig.playback.nowPlaying?.title == "Faixa 2")

        rig.playback.seek(to: 10)
        await rig.playback.skipToPrevious()
        #expect(rig.playback.nowPlaying?.title == "Faixa 2")
        #expect(rig.playback.playbackTime == 0)

        await rig.playback.skipToPrevious()
        #expect(rig.playback.nowPlaying?.title == "Faixa 1")
    }

    @Test("Repetir tudo dá a volta na fila; repetir uma mantém a faixa")
    func repeatModesAtQueueEnd() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)
        rig.fake.setRepeat(.all)
        for _ in 0..<3 { await rig.playback.skipToNext() }
        #expect(rig.playback.nowPlaying?.title == "Faixa 1")
        #expect(rig.playback.source != nil)

        rig.fake.setRepeat(.one)
        await rig.playback.skipToNext()
        #expect(rig.playback.nowPlaying?.title == "Faixa 1")
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

    @Test("Um fim de fila seguido de volta a tocar não esconde o tocador")
    func queueEndFollowedByPlayingKeepsPlayer() async throws {
        let rig = try await makeRig(endConfirmationDelay: .milliseconds(150))
        defer { cleanup(rig) }
        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)

        rig.fake.finishQueue()
        #expect(rig.playback.source != nil)
        // O tocador volta a tocar antes de o prazo acabar.
        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)
        try await Task.sleep(for: .milliseconds(300))

        #expect(rig.playback.source?.itemID == rig.ids[0])
        #expect(rig.playback.phase(of: rig.ids[0]) == .playing)
    }

    @Test("O fim da fila confirmado depois do prazo esconde o tocador")
    func confirmedQueueEndClearsAfterDelay() async throws {
        let rig = try await makeRig(endConfirmationDelay: .milliseconds(100))
        defer { cleanup(rig) }
        await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID)

        rig.fake.finishQueue()
        #expect(rig.playback.source != nil)
        try await Task.sleep(for: .milliseconds(400))

        #expect(rig.playback.source == nil)
    }

    @Test("Resumo: título e artista vêm da entrada atual; sem ela, do cartão")
    func summaryTitleAndArtist() async throws {
        let rig = try await makeRig(snapshots: [
            MusicSnapshot(kind: .album, catalogID: "100", title: "Álbum A", subtitle: "Banda do Cartão")
        ])
        defer { cleanup(rig) }
        let tabs = MuralTabs(registry: BoardSessionRegistry(library: BoardLibrary(rootDirectory: rig.directory)))
        rig.fake.playDelay = .milliseconds(200)

        let task = Task { await rig.playback.toggle(rig.ids[0], in: rig.model, boardID: rig.boardID) }
        while !rig.playback.isLoading { await Task.yield() }
        let loading = try #require(rig.playback.summary(in: tabs))
        #expect(loading.title == "Álbum A")
        #expect(loading.artist == "Banda do Cartão")
        #expect(loading.phase == .loading)
        await task.value

        let playing = try #require(rig.playback.summary(in: tabs))
        #expect(playing.title == "Faixa 1")
        #expect(playing.artist == "Artista")
        #expect(playing.duration == 180)
        #expect(playing.phase == .playing)
        #expect(playing.canSkipBackward)
    }

    @Test("Resumo: sem aba aberta, usa os nomes guardados na fonte")
    func summaryUsesStoredNamesWithoutTab() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        let tabs = MuralTabs(registry: BoardSessionRegistry(library: BoardLibrary(rootDirectory: rig.directory)))
        await rig.playback.toggle(
            rig.ids[0], in: rig.model, boardID: rig.boardID, route: .saved(rig.boardID), boardTitle: "Meu mural")

        let summary = try #require(rig.playback.summary(in: tabs))
        #expect(summary.boardTitle == "Meu mural")
        #expect(summary.cardTitle == "Álbum A")
        #expect(summary.sourceLine == "No mural Meu mural · Álbum A")
        #expect(summary.route == .saved(rig.boardID))
    }

    @Test("Resumo: sem música, nada")
    func summaryIsNilWhenIdle() async throws {
        let rig = try await makeRig()
        defer { cleanup(rig) }
        let tabs = MuralTabs(registry: BoardSessionRegistry(library: BoardLibrary(rootDirectory: rig.directory)))
        #expect(rig.playback.summary(in: tabs) == nil)
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
