import Foundation
import MuralKit
import Testing

@testable import Mural

/// Sem rede: o buscador é falso, o mural fica numa pasta temporária e grava na hora (modo imediato).
@MainActor
struct LinkPreviewCoordinatorTests {
    private static let oneHour: TimeInterval = 3_600

    @Test("Um pedido leva o cartão a pronto, com resumo, e deixa os arquivos gravados")
    func requestMakesTheCardReady() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let coordinator = harness.makeCoordinator()

        coordinator.request([harness.linkID])
        await coordinator.waitUntilIdle()

        let link = try harness.link()
        guard case .ready = link.preview else {
            Issue.record("a prévia deveria estar pronta: \(link.preview)")
            return
        }
        #expect(link.pageTitle == "Título buscado")
        #expect(link.siteName == "Site buscado")
        #expect(link.summary == "Resumo buscado")
        let image = try #require(link.previewImageFile)
        let icon = try #require(link.iconFile)
        #expect(FileManager.default.fileExists(atPath: harness.files.url(for: image).path))
        #expect(FileManager.default.fileExists(atPath: harness.files.url(for: icon).path))
        #expect(await harness.fetcher.requests.map(\.itemID) == [harness.linkID])

        let saved = try #require(try BoardStore(directory: harness.storeDirectory).load())
        #expect(saved.item(id: harness.linkID)?.link?.summary == "Resumo buscado", "o resultado foi gravado no disco")
    }

    @Test("Um segundo pedido sem force não busca de novo; com force busca e a varredura apaga os arquivos antigos")
    func forceFetchesAgainAndTheSweepRemovesTheOldFiles() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let coordinator = harness.makeCoordinator()
        coordinator.request([harness.linkID])
        await coordinator.waitUntilIdle()
        let first = try harness.link()
        let firstImage = try #require(first.previewImageFile)
        let firstIcon = try #require(first.iconFile)

        coordinator.request([harness.linkID])
        await coordinator.waitUntilIdle()
        #expect(await harness.fetcher.requests.count == 1, "prévia pronta não é buscada de novo")

        // Os arquivos da primeira busca ficam velhos; a varredura que segue a próxima entrega os apaga.
        try harness.age(firstImage, by: 2 * Self.oneHour)
        try harness.age(firstIcon, by: 2 * Self.oneHour)
        coordinator.request([harness.linkID], force: true)
        await coordinator.waitUntilIdle()

        #expect(await harness.fetcher.requests.count == 2, "com force a prévia é buscada de novo")
        let second = try harness.link()
        let secondImage = try #require(second.previewImageFile)
        let secondIcon = try #require(second.iconFile)
        #expect(secondImage != firstImage && secondIcon != firstIcon)
        #expect(harness.exists(secondImage) && harness.exists(secondIcon), "os arquivos em uso ficam")
        #expect(!harness.exists(firstImage) && !harness.exists(firstIcon), "os antigos e sem uso são apagados")
    }

    @Test("A varredura do começo apaga só o arquivo antigo e sem uso")
    func initialSweepRemovesOnlyOldUnusedFiles() async throws {
        let link = LinkInfo(
            url: URL(string: "https://exemplo.com/artigo")!, previewImageFile: "antigo-em-uso.jpg",
            preview: .ready(fetchedAt: .now))
        let harness = try Harness(link: link)
        defer { harness.tearDown() }
        try FileManager.default.createDirectory(at: harness.files.directory, withIntermediateDirectories: true)
        for name in ["antigo-sem-uso.jpg", "antigo-em-uso.jpg", "novo-sem-uso.jpg"] {
            try Data("arquivo".utf8).write(to: harness.files.url(for: name))
        }
        try harness.age("antigo-sem-uso.jpg", by: 2 * Self.oneHour)
        try harness.age("antigo-em-uso.jpg", by: 2 * Self.oneHour)

        let coordinator = harness.makeCoordinator(sweepMinimumAge: Self.oneHour)
        await coordinator.waitUntilIdle()

        #expect(!harness.exists("antigo-sem-uso.jpg"), "antigo e sem uso é apagado")
        #expect(harness.exists("antigo-em-uso.jpg"), "antigo mas em uso fica")
        #expect(harness.exists("novo-sem-uso.jpg"), "sem uso mas recente fica: pode estar a caminho do cartão")
    }

    @Test("Cancelar descarta a busca em andamento e o coordenador continua utilizável")
    func cancelAllDiscardsTheFetchAndTheCoordinatorStillWorks() async throws {
        let harness = try Harness(fetchDelay: .seconds(30))
        defer { harness.tearDown() }
        let coordinator = harness.makeCoordinator()

        coordinator.request([harness.linkID])
        await waitUntil("a busca começar") { await harness.fetcher.requests.count == 1 }
        coordinator.cancelAll()
        await coordinator.waitUntilIdle()

        let cancelled = try harness.link()
        guard case .pending = cancelled.preview else {
            Issue.record("a busca cancelada não deveria deixar resultado: \(cancelled.preview)")
            return
        }
        #expect(cancelled.previewImageFile == nil && cancelled.iconFile == nil)

        await harness.fetcher.setDelay(nil)
        coordinator.request([harness.linkID])
        await coordinator.waitUntilIdle()
        guard case .ready = try harness.link().preview else {
            Issue.record("depois de cancelar, um novo pedido deveria funcionar")
            return
        }
    }

    @Test("Pedido para um cartão que não existe não busca nada")
    func requestForAMissingItemIsIgnored() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let coordinator = harness.makeCoordinator()

        coordinator.request([UUID()])
        await coordinator.waitUntilIdle()

        #expect(await harness.fetcher.requests.isEmpty)
    }
}

/// O buscador de exemplo dos testes de interface precisa entregar dados que a gravação das prévias aceite.
struct FixtureLinkPreviewFetcherTests {
    @Test("Devolve a página de exemplo, com imagem e ícone que viram arquivos de prévia")
    func fixtureFeedsThePreviewFiles() async throws {
        let request = LinkPreviewRequest(itemID: UUID(), url: URL(string: "https://exemplo.com/artigo")!)
        let fetched = try await FixtureLinkPreviewFetcher().fetchPreview(for: request)

        #expect(fetched.title == "Página de exemplo")
        #expect(fetched.siteName == "Exemplo")
        #expect(fetched.summary == "Resumo de teste do Mural.")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MuralTests-Fixture-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let names = try LinkPreviewFiles(directory: directory).store(
            imageData: fetched.imageData, iconData: fetched.iconData, for: request.itemID)
        #expect(names.image != nil, "a imagem de exemplo é aceita pela gravação")
        #expect(names.icon != nil, "o ícone de exemplo é aceito pela gravação")
    }
}

// MARK: - Apoio

/// Buscador de mentira: guarda os pedidos e devolve sempre a mesma página, depois de `delay` se houver.
private actor FakeFetcher: LinkPreviewFetching {
    private(set) var requests: [LinkPreviewRequest] = []
    private var delay: Duration?
    private let image: Data
    private let icon: Data

    init(delay: Duration? = nil) throws {
        self.delay = delay
        image = try TestImage.png(width: 200, height: 120)
        icon = try TestImage.png(width: 32, height: 32)
    }

    func setDelay(_ delay: Duration?) {
        self.delay = delay
    }

    func fetchPreview(for request: LinkPreviewRequest) async throws -> FetchedLinkPreview {
        requests.append(request)
        if let delay { try await Task.sleep(for: delay) }
        return FetchedLinkPreview(
            title: "Título buscado", siteName: "Site buscado", summary: "Resumo buscado", imageData: image, iconData: icon)
    }
}

/// Um mural com um cartão de link, a pasta das prévias e o buscador falso, tudo numa pasta temporária.
@MainActor
private final class Harness {
    let directory: URL
    let storeDirectory: URL
    let model: BoardModel
    let files: LinkPreviewFiles
    let fetcher: FakeFetcher
    let linkID: UUID

    init(link: LinkInfo = LinkInfo(url: URL(string: "https://exemplo.com/artigo")!), fetchDelay: Duration? = nil) throws {
        let id = UUID()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MuralTests-LinkPreviewCoordinator-\(UUID().uuidString)", isDirectory: true)
        let storeDirectory = directory.appendingPathComponent("Mural", isDirectory: true)
        self.linkID = id
        self.directory = directory
        self.storeDirectory = storeDirectory
        model = BoardModel(
            board: Board(items: [BoardItem(id: id, kind: .link, title: "exemplo.com", link: link)]),
            store: BoardStore(directory: storeDirectory), persistence: .immediate)
        files = LinkPreviewFiles(directory: directory.appendingPathComponent("LinkPreviews", isDirectory: true))
        fetcher = try FakeFetcher(delay: fetchDelay)
    }

    /// Resultados na hora e varredura 10 ms depois de cada entrega.
    func makeCoordinator(sweepMinimumAge: TimeInterval = 3_600) -> LinkPreviewCoordinator {
        LinkPreviewCoordinator(
            model: model, files: files, fetcher: fetcher, batchDelay: .zero, sweepDelay: .milliseconds(10),
            sweepMinimumAge: sweepMinimumAge)
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    func link() throws -> LinkInfo {
        try #require(model.item(id: linkID)?.link)
    }

    func exists(_ fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: files.url(for: fileName).path)
    }

    /// Faz o arquivo parecer `seconds` mais velho.
    func age(_ fileName: String, by seconds: TimeInterval) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -seconds)], ofItemAtPath: files.url(for: fileName).path)
    }
}
