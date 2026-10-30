import Foundation
import MuralKit
import Testing

@testable import Mural

/// Sem rede: o buscador é falso e o mural fica numa pasta temporária.
@MainActor
struct MusicArtworkCoordinatorTests {
    @Test("Baixa a capa, grava na pasta e preenche artworkFile")
    func downloadsAndFillsTheArtwork() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let coordinator = harness.makeCoordinator()

        coordinator.request([harness.itemID])
        await coordinator.waitUntilIdle()

        let name = try #require(harness.music()?.artworkFile)
        #expect(harness.files.existingURL(for: name) != nil)
        #expect(await harness.fetcher.requests.map(\.absoluteString) == ["https://is1-ssl.mzstatic.com/capa/600x600.jpg"])
    }

    @Test("Capa já presente na pasta não é buscada")
    func existingArtworkIsNotFetched() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let name = try #require(
            try harness.files.store(
                imageData: try await FixtureMusicArtworkFetcher().fetchArtwork(at: harness.address), iconData: nil, for: harness.itemID
            ).image)
        var music = try #require(harness.music())
        music.artworkFile = name
        harness.model.updateMusic(harness.itemID, with: music)

        let coordinator = harness.makeCoordinator()
        coordinator.request([harness.itemID])
        await coordinator.waitUntilIdle()

        #expect(await harness.fetcher.requests.isEmpty)
    }

    @Test("Sem molde de endereço não busca")
    func withoutTemplateNothingIsFetched() async throws {
        let harness = try Harness(template: nil)
        defer { harness.tearDown() }
        let coordinator = harness.makeCoordinator()

        coordinator.request([harness.itemID])
        await coordinator.waitUntilIdle()

        #expect(await harness.fetcher.requests.isEmpty)
        #expect(harness.music()?.artworkFile == nil)
    }

    @Test("Falha não preenche e não tenta de novo na mesma janela")
    func failureIsNotRetried() async throws {
        let harness = try Harness(fails: true)
        defer { harness.tearDown() }
        let coordinator = harness.makeCoordinator()

        coordinator.request([harness.itemID])
        await coordinator.waitUntilIdle()
        coordinator.request([harness.itemID])
        await coordinator.waitUntilIdle()

        #expect(harness.music()?.artworkFile == nil)
        #expect(await harness.fetcher.requests.count == 1)
    }

    @Test("store grava a capa que veio no arrasto e preenche artworkFile, sem baixar")
    func storeWritesWithoutDownloading() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let coordinator = harness.makeCoordinator()
        let data = try await FixtureMusicArtworkFetcher().fetchArtwork(at: harness.address)

        coordinator.store(data, for: harness.itemID)
        await coordinator.waitUntilIdle()

        let name = try #require(harness.music()?.artworkFile)
        #expect(harness.files.existingURL(for: name) != nil)
        #expect(await harness.fetcher.requests.isEmpty)
    }

    @Test("download baixa o endereço pronto, mesmo sem molde")
    func downloadUsesTheGivenAddress() async throws {
        let harness = try Harness(template: nil)
        defer { harness.tearDown() }
        let coordinator = harness.makeCoordinator()

        coordinator.download(harness.address, for: harness.itemID)
        await coordinator.waitUntilIdle()

        let name = try #require(harness.music()?.artworkFile)
        #expect(harness.files.existingURL(for: name) != nil)
        #expect(await harness.fetcher.requests == [harness.address])
    }

    @Test("download respeita capa no disco e falha anterior")
    func downloadHonorsGuards() async throws {
        let failing = try Harness(template: nil, fails: true)
        defer { failing.tearDown() }
        let coordinator = failing.makeCoordinator()
        coordinator.download(failing.address, for: failing.itemID)
        await coordinator.waitUntilIdle()
        coordinator.download(failing.address, for: failing.itemID)
        await coordinator.waitUntilIdle()
        #expect(await failing.fetcher.requests.count == 1)
        #expect(failing.music()?.artworkFile == nil)

        let harness = try Harness(template: nil)
        defer { harness.tearDown() }
        let name = try #require(
            try harness.files.store(
                imageData: try await FixtureMusicArtworkFetcher().fetchArtwork(at: harness.address), iconData: nil, for: harness.itemID
            ).image)
        var music = try #require(harness.music())
        music.artworkFile = name
        harness.model.updateMusic(harness.itemID, with: music)
        let other = harness.makeCoordinator()
        other.download(harness.address, for: harness.itemID)
        await other.waitUntilIdle()
        #expect(await harness.fetcher.requests.isEmpty)
    }

    @Test("Cartão apagado antes de aplicar: nada muda e o arquivo gravado é descartado")
    func deletedCardIsLeftAlone() async throws {
        let harness = try Harness(delay: .milliseconds(150))
        defer { harness.tearDown() }
        let coordinator = harness.makeCoordinator()

        coordinator.request([harness.itemID])
        harness.model.delete(harness.itemID)
        await coordinator.waitUntilIdle()

        #expect(harness.model.item(id: harness.itemID) == nil)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: harness.files.directory.path)) ?? []
        #expect(leftovers.isEmpty)
    }
}

/// Buscador falso: registra os endereços pedidos e devolve um PNG, falha ou espera um tempo antes.
private actor FakeArtworkFetcher: MusicArtworkFetching {
    private(set) var requests: [URL] = []
    private let fails: Bool
    private let delay: Duration?

    init(fails: Bool, delay: Duration?) {
        self.fails = fails
        self.delay = delay
    }

    func fetchArtwork(at url: URL) async throws -> Data {
        requests.append(url)
        if let delay { try await Task.sleep(for: delay) }
        if fails { throw URLError(.badServerResponse) }
        return try await FixtureMusicArtworkFetcher().fetchArtwork(at: url)
    }
}

@MainActor
private final class Harness {
    let directory: URL
    let model: BoardModel
    let files: LinkPreviewFiles
    let fetcher: FakeArtworkFetcher
    let itemID = UUID()
    let address = URL(string: "https://is1-ssl.mzstatic.com/capa/600x600.jpg")!

    init(template: String? = "https://is1-ssl.mzstatic.com/capa/{w}x{h}.{f}", fails: Bool = false, delay: Duration? = nil) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MuralTests-MusicArtwork-\(UUID().uuidString)", isDirectory: true)
        let music = MusicSnapshot(kind: .album, catalogID: "1", title: "Álbum de teste", artworkTemplate: template)
        model = BoardModel(
            board: Board(items: [BoardItem(id: itemID, kind: .music, title: music.title, music: music)]),
            store: BoardStore(directory: directory.appendingPathComponent("Mural", isDirectory: true)), persistence: .immediate)
        files = LinkPreviewFiles(directory: directory.appendingPathComponent("LinkPreviews", isDirectory: true))
        fetcher = FakeArtworkFetcher(fails: fails, delay: delay)
    }

    func makeCoordinator() -> MusicArtworkCoordinator {
        MusicArtworkCoordinator(model: model, files: files, fetcher: fetcher)
    }

    func music() -> MusicSnapshot? { model.item(id: itemID)?.music }

    func tearDown() { try? FileManager.default.removeItem(at: directory) }
}
