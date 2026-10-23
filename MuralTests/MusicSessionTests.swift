import CoreGraphics
import Foundation
import MuralKit
import Testing

@testable import Mural

@Suite("Música na sessão")
@MainActor
struct MusicSessionTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralMusicSession-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeReady(_ session: BoardWindowSession) async {
        await session.load()
        let metrics = CanvasScrollMetrics(
            contentOffset: .zero, containerSize: CGSize(width: 900, height: 700), contentSize: CGSize(width: 3_400, height: 2_800))
        for _ in 0..<3 where session.restorationPhase != .ready {
            session.restoreCanvas(boardID: session.boardID, generation: session.presentationGeneration, metrics: metrics)
        }
        #expect(session.restorationPhase == .ready)
    }

    @Test("Cria os cartões na pasta, com o título do item, e entrega a capa do arrasto ao coordenador")
    func createsCardsAndHandsOverTheArtwork() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Música")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        await makeReady(session)
        let model = try #require(session.model)
        let folder = model.createFolder(named: "Pasta")
        let files = LinkPreviewFiles(directory: directory.appendingPathComponent("Capas", isDirectory: true))
        let coordinator = MusicArtworkCoordinator(model: model, files: files, fetcher: FixtureMusicArtworkFetcher())

        let artwork = try await FixtureMusicArtworkFetcher().fetchArtwork(at: try #require(URL(string: "https://exemplo.com/a")))
        let drafts = [
            MusicDraft(snapshot: MusicSnapshot(kind: .song, title: "Faixa de teste", subtitle: "Artista"), artworkData: artwork),
            MusicDraft(snapshot: MusicSnapshot(kind: .playlist, libraryPlaylistName: "Lista", title: "Lista")),
        ]
        let ids = session.importMusic(drafts, into: folder.id, artwork: coordinator, animation: nil)
        await coordinator.waitUntilIdle()

        #expect(ids.count == 2)
        let items = ids.compactMap { model.item(id: $0) }
        #expect(items.map(\.title) == ["Faixa de teste", "Lista"])
        #expect(items.allSatisfy { $0.kind == .music && $0.parentID == folder.id })
        let name = try #require(items[0].music?.artworkFile)
        #expect(files.existingURL(for: name) != nil)
        #expect(items[1].music?.artworkFile == nil)
        #expect(model.lastError == nil)
    }

    @Test("Lista vazia avisa em lastError e não cria cartão")
    func emptyDraftsReportAnError() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Música")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        await makeReady(session)
        let model = try #require(session.model)

        let ids = session.importMusic([], into: nil, artwork: nil, animation: nil)

        #expect(ids.isEmpty)
        #expect(model.musicItems.isEmpty)
        #expect(model.lastError == "O conteúdo copiado não pôde virar um cartão.")
    }
}
