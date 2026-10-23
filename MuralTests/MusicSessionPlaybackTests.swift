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
}
