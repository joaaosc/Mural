import CoreGraphics
import Foundation
import MuralKit
import Testing

@testable import Mural

/// `completeMusicArtwork` na sessão, com Apple Music e buscador falsos. A pasta de prévias do mural novo
/// (UUID próprio) é apagada no fim.
@Suite("Capa do catálogo na sessão")
@MainActor
struct MusicSessionArtworkTests {
    @MainActor private struct Rig {
        let directory: URL
        let previews: URL
        let session: BoardWindowSession
        let model: BoardModel
        let fake: FakeMusic
        let coordinator: MusicArtworkCoordinator
        let id: UUID

        func music() -> MusicSnapshot? { model.item(id: id)?.music }
        func tearDown() {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: previews)
        }
    }

    private let address = URL(string: "https://is1-ssl.mzstatic.com/capa/600x600.jpg")!

    private func makeRig(
        access: MusicAccess = .granted, template: String? = nil, snapshot: MusicSnapshot? = nil
    ) async throws -> Rig {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralMusicSessionArtwork-\(UUID().uuidString)", isDirectory: true)
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
        fake.access = access
        fake.artwork = MusicCatalogArtwork(
            url: address, backgroundHex: "#111111", primaryTextHex: "#222222", secondaryTextHex: "#333333")
        session.musicPlayback = MusicPlayback(provider: fake)
        let draft =
            snapshot ?? MusicSnapshot(kind: .album, catalogID: "100", title: "Álbum A", artworkTemplate: template)
        let ids = session.importMusic([MusicDraft(snapshot: draft)], into: nil, artwork: nil, animation: nil)
        let model = try #require(session.model)
        let previews = LaunchConfiguration.linkPreviewsDirectory(for: session.boardID)
        let coordinator = MusicArtworkCoordinator(
            model: model, files: LinkPreviewFiles(directory: previews), fetcher: FixtureMusicArtworkFetcher())
        return Rig(
            directory: directory, previews: previews, session: session, model: model, fake: fake, coordinator: coordinator,
            id: try #require(ids.first))
    }

    @Test("Grava a capa e as cores que faltavam")
    func fillsArtworkAndColors() async throws {
        let rig = try await makeRig()
        defer { rig.tearDown() }

        await rig.session.completeMusicArtwork(rig.id, artwork: rig.coordinator)
        await rig.coordinator.waitUntilIdle()

        let music = try #require(rig.music())
        let name = try #require(music.artworkFile)
        #expect(LinkPreviewFiles(directory: rig.previews).existingURL(for: name) != nil)
        #expect(music.backgroundHex == "#111111")
        #expect(music.primaryTextHex == "#222222")
        #expect(music.secondaryTextHex == "#333333")
    }

    @Test("Mantém as cores que o cartão já tinha")
    func keepsExistingColors() async throws {
        let rig = try await makeRig(
            snapshot: MusicSnapshot(kind: .album, catalogID: "100", title: "Álbum A", backgroundHex: "#abcdef"))
        defer { rig.tearDown() }

        await rig.session.completeMusicArtwork(rig.id, artwork: rig.coordinator)
        await rig.coordinator.waitUntilIdle()

        let music = try #require(rig.music())
        #expect(music.backgroundHex == "#abcdef")
        #expect(music.primaryTextHex == "#222222")
        #expect(music.artworkFile != nil)
    }

    @Test("Sem acesso concedido não faz nada")
    func withoutAccessNothingHappens() async throws {
        let rig = try await makeRig(access: .notDetermined)
        defer { rig.tearDown() }

        await rig.session.completeMusicArtwork(rig.id, artwork: rig.coordinator)
        await rig.coordinator.waitUntilIdle()

        #expect(rig.fake.requestAccessCount == 0)
        #expect(rig.music()?.artworkFile == nil)
        #expect(rig.music()?.backgroundHex == nil)
    }

    @Test("Com molde de endereço não faz nada")
    func withTemplateNothingHappens() async throws {
        let rig = try await makeRig(template: "https://is1-ssl.mzstatic.com/capa/{w}x{h}.{f}")
        defer { rig.tearDown() }

        await rig.session.completeMusicArtwork(rig.id, artwork: rig.coordinator)
        await rig.coordinator.waitUntilIdle()

        #expect(rig.music()?.artworkFile == nil)
        #expect(rig.music()?.backgroundHex == nil)
    }
}
