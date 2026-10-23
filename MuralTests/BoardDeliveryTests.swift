import CoreGraphics
import Foundation
import MuralKit
import Testing

@testable import Mural

/// A entrega do que foi copiado a um mural escolhido: aberto numa aba, numa aba de fundo ainda não carregada, fechando
/// ou fechado. Em nenhum caso existem duas sessões do mesmo mural, senão o salvamento de uma apagaria o cartão da outra.
@Suite("Entrega ao mural escolhido", .serialized)
@MainActor
struct BoardDeliveryTests {
    // MARK: Mural fechado

    @Test("Mural fechado: o texto vira post-it no disco, a capa é refeita e nenhuma sessão sobra")
    func deliversToClosedBoard() async throws {
        let workspace = try DeliveryWorkspace()
        defer { workspace.removeFiles() }
        let entry = try await workspace.makeEntry("Fechado")
        let id = entry.manifest.id

        let outcome = await workspace.delivery.deliver(.pasted(.text("Comprar leite")), textKind: .sticky, to: entry)

        #expect(outcome == .delivered(count: 1))
        let board = try await workspace.savedBoard(entry)
        let sticky = try #require(board.items.first { $0.kind == .sticky })
        #expect(sticky.text == "Comprar leite")
        #expect(sticky.parentID == nil, "o cartão entra na raiz do mural")
        #expect(workspace.delivery.detachedSession(for: id) == nil)
        #expect(workspace.liveSessions(of: id).isEmpty)
        #expect(await workspace.registry.ownerCount(for: id) == 0)

        // A capa nova leva a revisão que ficou gravada: a vitrine a reconhece como atual.
        let revision = try await workspace.savedRevision(entry)
        #expect(revision > 0)
        #expect(workspace.coverFiles.latest(for: id)?.revision == revision)
        await workspace.finish()
    }

    @Test("Mural que não existe: falha, e nenhuma sessão nem referência fica para trás")
    func failsForMissingBoard() async throws {
        let workspace = try DeliveryWorkspace()
        defer { workspace.removeFiles() }
        _ = try await workspace.library.bootstrap()
        let id = BoardID()
        let entry = BoardLibraryEntry(manifest: BoardManifest(id: id, name: "Fantasma"), route: .saved(id))

        let outcome = await workspace.delivery.deliver(.pasted(.text("Nada")), textKind: .sticky, to: entry)

        guard case .failed(let message) = outcome else {
            Issue.record("Esperava uma falha, veio \(outcome)")
            return
        }
        #expect(!message.isEmpty)
        #expect(workspace.delivery.detachedSession(for: id) == nil)
        #expect(workspace.liveSessions(of: id).isEmpty)
        #expect(await workspace.registry.ownerCount(for: id) == 0)
        await workspace.finish()
    }

    @Test("Sem nada para colar a entrega falha sem abrir o mural")
    func nothingToPasteLeavesTheBoardAlone() async throws {
        let workspace = try DeliveryWorkspace()
        defer { workspace.removeFiles() }
        let entry = try await workspace.makeEntry("Intocado")
        let id = entry.manifest.id

        let outcome = await workspace.delivery.deliver(.pasted(.nothing), textKind: nil, to: entry)

        #expect(outcome == .failed("Não há nada para colar."))
        #expect(workspace.delivery.detachedSession(for: id) == nil)
        #expect(await workspace.registry.ownerCount(for: id) == 0)
        #expect(try await workspace.savedRevision(entry) == 0, "o mural nem foi aberto")
        await workspace.finish()
    }

    @Test("Música, links e imagem viram cartões do tipo certo")
    func musicLinksAndImageBecomeCards() async throws {
        let workspace = try DeliveryWorkspace()
        defer { workspace.removeFiles() }
        let entry = try await workspace.makeEntry("Variado")
        let delivery = workspace.delivery

        let album = MusicSnapshot(kind: .album, catalogID: "1441164426", title: "Abbey Road", subtitle: "The Beatles")
        #expect(await delivery.deliver(.music([MusicDraft(snapshot: album)]), textKind: nil, to: entry) == .delivered(count: 1))

        let link = LinkDraft(url: try #require(URL(string: "https://example.com/artigo")))
        #expect(await delivery.deliver(.pasted(.links([link])), textKind: nil, to: entry) == .delivered(count: 1))

        let png = try TestImage.png(width: 64, height: 48)
        let photo = ClipboardContent.pasted(.data(png, fileExtension: "png", kind: .image, title: "Imagem colada"))
        #expect(await delivery.deliver(photo, textKind: nil, to: entry) == .delivered(count: 1))

        let board = try await workspace.savedBoard(entry)
        #expect(board.items.first { $0.kind == .music }?.music?.title == "Abbey Road")
        #expect(board.items.first { $0.kind == .link }?.link?.url.absoluteString == "https://example.com/artigo")
        let image = try #require(board.items.first { $0.kind == .image })
        #expect(image.title == "Imagem colada")
        #expect(image.fileName != nil)
        #expect(board.items.count == 3)
        #expect(workspace.liveSessions(of: entry.manifest.id).isEmpty)
        #expect(await workspace.registry.ownerCount(for: entry.manifest.id) == 0)
        await workspace.finish()
    }

    @Test("O cartão nasce perto do centro salvo do mural, não da origem")
    func cardLandsNearTheSavedCenter() async throws {
        let workspace = try DeliveryWorkspace()
        defer { workspace.removeFiles() }
        let route = try await workspace.library.createNamedBoard("Longe")
        var snapshot = try #require(try await workspace.library.open(route))
        snapshot.workspace.canvas = CanvasWorkspaceState(logicalCenter: BoardPoint(x: 2000, y: 1500))
        snapshot.manifest.workspaceRevision += 1
        try await workspace.library.repository(for: route).save(snapshot)
        let far = try #require(try await workspace.library.listSaved().first { $0.route == route })
        let origin = try await workspace.makeEntry("Perto")

        #expect(await workspace.delivery.deliver(.pasted(.text("Aqui")), textKind: .sticky, to: far) == .delivered(count: 1))
        #expect(await workspace.delivery.deliver(.pasted(.text("Ali")), textKind: .sticky, to: origin) == .delivered(count: 1))

        let farCard = try #require(try await workspace.savedBoard(far).items.first)
        #expect(abs(farCard.position.x - 2000) < 600 && abs(farCard.position.y - 1500) < 600, "\(farCard.position)")
        let originCard = try #require(try await workspace.savedBoard(origin).items.first)
        #expect(originCard.position.x < 600 && originCard.position.y < 600, "sem centro salvo, perto da origem: \(originCard.position)")
        await workspace.finish()
    }

    @Test("Duas entregas ao mesmo mural fechado, ao mesmo tempo, não se atropelam")
    func simultaneousDeliveriesAreSerial() async throws {
        let workspace = try DeliveryWorkspace()
        defer { workspace.removeFiles() }
        let entry = try await workspace.makeEntry("Fila")
        let delivery = workspace.delivery

        async let first = delivery.deliver(.pasted(.text("Primeiro")), textKind: .sticky, to: entry)
        async let second = delivery.deliver(.pasted(.text("Segundo")), textKind: .sticky, to: entry)
        let outcomes = await [first, second]

        #expect(outcomes == [.delivered(count: 1), .delivered(count: 1)])
        let board = try await workspace.savedBoard(entry)
        #expect(Set(board.items.compactMap(\.text)) == ["Primeiro", "Segundo"], "uma entrega não apaga o cartão da outra")
        #expect(await workspace.registry.ownerCount(for: entry.manifest.id) == 0)
        await workspace.finish()
    }

    // MARK: Mural com aba

    @Test("Mural aberto numa aba já carregada: o cartão entra no modelo da própria aba")
    func deliversIntoLoadedTab() async throws {
        let workspace = try DeliveryWorkspace()
        defer { workspace.removeFiles() }
        let entry = try await workspace.makeEntry("Aberto")
        let id = entry.manifest.id
        let tab = try #require(workspace.tabs.open(entry.route, title: "Aberto"))
        await waitUntil("a aba carregar") { tab.session.model != nil }

        let outcome = await workspace.delivery.deliver(.pasted(.text("Na aba")), textKind: .sticky, to: entry)

        #expect(outcome == .delivered(count: 1))
        #expect(tab.session.model?.board.items.contains { $0.text == "Na aba" } == true)
        let live = workspace.liveSessions(of: id)
        #expect(live.count == 1, "uma sessão só desse mural")
        #expect(live.first === tab.session)
        #expect(workspace.delivery.detachedSession(for: id) == nil)
        #expect(await workspace.registry.ownerCount(for: id) == 1)
        await workspace.finish()
    }

    @Test("Aba de fundo ainda não carregada: a entrega carrega a aba uma vez só, e escolhê-la depois não abre outra")
    func deliversIntoBackgroundTabOnce() async throws {
        let workspace = try DeliveryWorkspace()
        defer { workspace.removeFiles() }
        let background = try await workspace.makeEntry("Fundo")
        let selected = try await workspace.makeEntry("Na frente")
        let id = background.manifest.id
        workspace.tabs.restore(
            MuralTabsSnapshot(
                entries: [.init(route: background.route, title: "Fundo"), .init(route: selected.route, title: "Na frente")],
                selectedIndex: 1))
        let tab = try #require(workspace.tabs.tab(for: id))
        await waitUntil("a aba da frente carregar") { workspace.tabs.selected?.session.model != nil }
        #expect(tab.session.model == nil, "a aba de fundo ainda não carregou")

        let outcome = await workspace.delivery.deliver(.pasted(.text("No fundo")), textKind: .sticky, to: background)

        #expect(outcome == .delivered(count: 1))
        let model = try #require(tab.session.model)
        #expect(model.board.items.contains { $0.text == "No fundo" })
        #expect(await workspace.registry.ownerCount(for: id) == 1)

        // Escolher a aba agora pede o carregamento de novo; ele reaproveita o modelo e a referência.
        #expect(workspace.tabs.select(tab.id))
        await tab.session.load()
        for _ in 0..<10 { await Task.yield() }
        #expect(tab.session.model === model)
        #expect(await workspace.registry.ownerCount(for: id) == 1)
        #expect(workspace.liveSessions(of: id).count == 1)
        await workspace.finish()
    }

    @Test("Aba aberta no meio da entrega adota a sessão avulsa, que continua aberta e grava")
    func tabOpenedDuringDeliveryAdoptsTheSession() async throws {
        let workspace = try DeliveryWorkspace()
        defer { workspace.removeFiles() }
        let entry = try await workspace.makeEntry("Adoção")
        let id = entry.manifest.id

        let delivering = Task {
            await workspace.delivery.deliver(.pasted(.text("Chegou na aba")), textKind: .sticky, to: entry)
        }
        var polls = 0
        while workspace.delivery.detachedSession(for: id) == nil, polls < 20_000 {
            await Task.yield()
            polls += 1
        }
        let detached = try #require(workspace.delivery.detachedSession(for: id), "a entrega deveria ter aberto a sessão avulsa")

        let tab = try #require(workspace.tabs.open(entry.route, title: "Adoção"))
        #expect(tab.session === detached, "a aba fica com a sessão que a entrega abriu")
        #expect(workspace.delivery.detachedSession(for: id) == nil, "a sessão sai do mapa uma vez só")

        let outcome = await delivering.value

        #expect(outcome == .delivered(count: 1))
        #expect(tab.session.model?.board.items.contains { $0.text == "Chegou na aba" } == true)
        #expect(!tab.session.isClosed, "a entrega não fecha a sessão que agora é da aba")
        #expect(workspace.delivery.detachedSession(for: id) == nil)
        #expect(workspace.liveSessions(of: id).count == 1)
        #expect(await workspace.registry.ownerCount(for: id) == 1)

        await tab.session.flushAndPrepareToLeave()
        let board = try await workspace.savedBoard(entry)
        #expect(board.items.contains { $0.text == "Chegou na aba" }, "o cartão chegou ao disco")
        await workspace.finish()
    }

    @Test("Aba fechando: a entrega espera a aba gravar e fechar, e a edição dela não se perde")
    func waitsForTabThatIsClosing() async throws {
        let workspace = try DeliveryWorkspace()
        defer { workspace.removeFiles() }
        let entry = try await workspace.makeEntry("Fechando")
        let id = entry.manifest.id
        let tab = try #require(workspace.tabs.open(entry.route, title: "Fechando"))
        await waitUntil("a aba carregar") { tab.session.model != nil }
        let edited = try #require(tab.session.model?.importText("Edição da aba", as: .sticky))
        tab.session.captureBoardIfNeeded()

        // A aba sai da lista na hora; a gravação e o fechamento da sessão seguem em segundo plano.
        workspace.tabs.close(tab.id)
        #expect(workspace.tabs.tab(for: id) == nil)
        let outcome = await workspace.delivery.deliver(.pasted(.text("Depois do fechamento")), textKind: .sticky, to: entry)

        #expect(outcome == .delivered(count: 1))
        let board = try await workspace.savedBoard(entry)
        #expect(board.item(id: edited.id) != nil, "o que a aba tinha editado continua no mural")
        #expect(board.items.contains { $0.text == "Depois do fechamento" })
        #expect(tab.session.isClosed)
        #expect(workspace.delivery.detachedSession(for: id) == nil)
        #expect(workspace.liveSessions(of: id).isEmpty)
        #expect(await workspace.registry.ownerCount(for: id) == 0)
        await workspace.finish()
    }
}

// MARK: Apoio

/// Biblioteca temporária, abas, entrega e capas, tudo ligado como no app.
@MainActor
private final class DeliveryWorkspace {
    let directory: URL
    let library: BoardLibrary
    let registry: BoardSessionRegistry
    let coverFiles: BoardCoverFiles
    let covers: BoardCoverService
    let delivery: BoardDelivery
    let tabs: MuralTabs

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralDelivery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Mural excluído nos testes é apagado, não vai para o Lixo de quem roda os testes.
        let library = BoardLibrary(
            rootDirectory: directory.appendingPathComponent("Biblioteca", isDirectory: true),
            discardPackage: { try FileManager.default.removeItem(at: $0) })
        let registry = BoardSessionRegistry(library: library)
        let coverFiles = BoardCoverFiles(directory: directory.appendingPathComponent("Capas", isDirectory: true))
        let covers = BoardCoverService(
            library: library, files: coverFiles, liveBoards: { [] }, linkPreviewFiles: { _ in nil },
            render: { _, _, _ in tinyCoverImage() })
        let delivery = BoardDelivery(registry: registry, covers: covers)
        let tabs = MuralTabs(
            registry: registry,
            makeSession: { route in
                delivery.adoptDetachedSession(for: route) ?? BoardWindowSession(route: route, registry: registry)
            })
        delivery.tabs = tabs

        self.directory = directory
        self.library = library
        self.registry = registry
        self.coverFiles = coverFiles
        self.covers = covers
        self.delivery = delivery
        self.tabs = tabs
    }

    /// Cria um mural salvo vazio e devolve a entrada que a listagem da biblioteca mostraria.
    func makeEntry(_ name: String) async throws -> BoardLibraryEntry {
        let route = try await library.createNamedBoard(name)
        return try #require(try await library.listSaved().first { $0.route == route })
    }

    /// O conteúdo do mural como está no disco.
    func savedBoard(_ entry: BoardLibraryEntry) async throws -> Board {
        try #require(try await library.readBoard(entry.route))
    }

    /// A revisão do conteúdo gravada no disco.
    func savedRevision(_ entry: BoardLibraryEntry) async throws -> Int {
        let saved = try #require(try await library.listSaved().first { $0.route == entry.route })
        return saved.manifest.contentRevision
    }

    /// As sessões de janela abertas desse mural, em qualquer lugar do app.
    func liveSessions(of id: BoardID) -> [BoardWindowSession] {
        OpenBoardSessions.shared.live.filter { $0.boardID == id }
    }

    /// Fecha as abas (gravando) e espera as capas terminarem.
    func finish() async {
        await tabs.closeAll()
        await covers.waitUntilIdle()
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Uma imagem pequena qualquer: basta para a capa ser gravada com a revisão.
private func tinyCoverImage() -> CGImage? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.setFillColor(red: 0.9, green: 0.8, blue: 0.2, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    return context.makeImage()
}
