import CoreGraphics
import Foundation
import MuralKit
import Testing

@testable import Mural

@Suite("Tocador na sessão")
@MainActor
struct MusicSessionPlaybackTests {
    private struct Rig {
        let directory: URL
        let session: BoardWindowSession
        let model: BoardModel
        let ids: [UUID]
        let fake: FakeMusic
    }

    private func makeRig() async throws -> Rig {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralMusicSessionPlayback-\(UUID().uuidString)", isDirectory: true)
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
        let fake = FakeMusic(arguments: [])
        session.musicPlayback = MusicPlayback(provider: fake)
        let ids = session.importMusic(
            [
                MusicDraft(snapshot: MusicSnapshot(kind: .album, catalogID: "100", title: "Álbum A")),
                MusicDraft(snapshot: MusicSnapshot(kind: .song, catalogID: "200", title: "Faixa B")),
            ], into: nil, artwork: nil, animation: nil)
        try #require(ids.count == 2)
        return Rig(directory: directory, session: session, model: try #require(session.model), ids: ids, fake: fake)
    }

    @Test("toggleMusic toca e pausa, e musicPhase acompanha")
    func toggleAndPhase() async throws {
        let rig = try await makeRig()
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        let id = rig.ids[0]

        #expect(rig.session.musicPhase(of: id) == .idle)
        await rig.session.toggleMusic(id)
        #expect(rig.fake.played.count == 1)
        #expect(rig.session.musicPhase(of: id) == .playing)
        #expect(rig.session.musicPhase(of: rig.ids[1]) == .idle)

        await rig.session.toggleMusic(id)
        #expect(rig.fake.pauseCount == 1)
        #expect(rig.session.musicPhase(of: id) == .paused)
    }

    @Test("playMusic repassa a faixa inicial")
    func playFromTrack() async throws {
        let rig = try await makeRig()
        defer { try? FileManager.default.removeItem(at: rig.directory) }

        await rig.session.playMusic(rig.ids[0], startingAt: "faixa-2")

        #expect(rig.fake.played.first?.1 == "faixa-2")
    }

    @Test("Apagar o cartão que toca para o tocador")
    func deletingThePlayingCardStops() async throws {
        let rig = try await makeRig()
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        await rig.session.toggleMusic(rig.ids[0])

        rig.session.delete(rig.ids[0])

        #expect(rig.fake.stopCount == 1)
        #expect(rig.session.musicPhase(of: rig.ids[0]) == .idle)
    }

    @Test("Apagar outro cartão não para")
    func deletingAnotherCardKeepsPlaying() async throws {
        let rig = try await makeRig()
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        await rig.session.toggleMusic(rig.ids[0])

        rig.session.delete(rig.ids[1])

        #expect(rig.fake.stopCount == 0)
        #expect(rig.session.musicPhase(of: rig.ids[0]) == .playing)
    }

    @Test("Apagar a pasta com o cartão dentro para o tocador")
    func deletingTheFolderStops() async throws {
        let rig = try await makeRig()
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        let folder = rig.model.createFolder(named: "Pasta")
        rig.session.moveIntoFolder(rig.ids[0], folderID: folder.id)
        await rig.session.toggleMusic(rig.ids[0])
        #expect(rig.fake.stopCount == 0)

        rig.session.delete(folder.id)

        #expect(rig.fake.stopCount == 1)
        #expect(rig.session.musicPhase(of: rig.ids[0]) == .idle)
    }

    @Test("Fechar a janela do mural não para a música")
    func closingTheWindowKeepsPlaying() async throws {
        let rig = try await makeRig()
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        await rig.session.toggleMusic(rig.ids[0])

        await rig.session.handleWindowWillClose()

        #expect(rig.fake.stopCount == 0)
        #expect(rig.session.musicPlayback.source?.itemID == rig.ids[0])
        #expect(rig.fake.status == .playing)
    }

    @Test("Promover o rascunho continua tocando e aponta para o mural salvo")
    func promotingTheDraftKeepsPlaying() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralMusicDraft-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let state = try await library.bootstrap()
        let session = BoardWindowSession(
            route: .welcomeDraft(state.stableWelcomeID), registry: BoardSessionRegistry(library: library))
        await session.load()
        let metrics = CanvasScrollMetrics(
            contentOffset: .zero, containerSize: CGSize(width: 900, height: 700), contentSize: CGSize(width: 3_400, height: 2_800))
        session.restoreCanvas(boardID: session.boardID, generation: session.presentationGeneration, metrics: metrics)
        // O rascunho de boas-vindas abre numa posição própria: a segunda medida já chega lá.
        let reached = CanvasScrollMetrics(
            contentOffset: session.restoreTarget ?? .zero, containerSize: metrics.containerSize,
            contentSize: metrics.contentSize, contentInsets: metrics.contentInsets)
        for _ in 0..<3 where session.restorationPhase != .ready {
            session.restoreCanvas(boardID: session.boardID, generation: session.presentationGeneration, metrics: reached)
        }
        try #require(session.restorationPhase == .ready)
        let fake = FakeMusic(arguments: [])
        let playback = MusicPlayback(provider: fake)
        session.musicPlayback = playback
        let ids = session.importMusic(
            [MusicDraft(snapshot: MusicSnapshot(kind: .album, catalogID: "100", title: "Álbum A"))],
            into: nil, artwork: nil, animation: nil)
        await session.toggleMusic(try #require(ids.first))
        #expect(playback.source?.route == .welcomeDraft(state.stableWelcomeID))

        let promoted = try #require(await session.promoteDraft(named: "Promovido"))

        #expect(fake.stopCount == 0)
        #expect(fake.status == .playing)
        #expect(playback.source?.route == promoted)
        #expect(playback.source?.boardTitle == "Promovido")
        guard case .saved(let savedID) = promoted else {
            Issue.record("a rota promovida deveria ser salva")
            return
        }
        #expect(playback.source?.boardID == savedID)
    }

    @Test("Renomear o mural atualiza o nome na fonte")
    func renamingUpdatesTheSourceTitle() async throws {
        let rig = try await makeRig()
        defer { try? FileManager.default.removeItem(at: rig.directory) }
        await rig.session.toggleMusic(rig.ids[0])
        #expect(rig.session.musicPlayback.source?.boardTitle == "Música")

        await rig.session.rename(to: "Novo nome")

        #expect(rig.session.musicPlayback.source?.boardTitle == "Novo nome")
        #expect(rig.fake.stopCount == 0)
    }
}
