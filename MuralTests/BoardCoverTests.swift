import CoreGraphics
import Foundation
import ImageIO
import MuralKit
import SwiftUI
import Testing
import UniformTypeIdentifiers

@testable import Mural

/// Conta e, se pedido, segura os desenhos de capa que o serviço faz; quem desenha de verdade é `BoardCoverRenderer`.
@MainActor
private final class CoverRenderProbe {
    private(set) var calls = 0
    private(set) var drawnBoards: [Board] = []
    /// Verdadeiro enquanto um desenho está parado esperando `release()`.
    private(set) var isWaiting = false
    /// Com isto ligado, o próximo desenho para até `release()`.
    var holdsRenders = false
    private var gate: CheckedContinuation<Void, Never>?

    func render(_ board: Board, _ model: BoardModel, _ files: LinkPreviewFiles?) async -> CGImage? {
        calls += 1
        drawnBoards.append(board)
        if holdsRenders {
            isWaiting = true
            await withCheckedContinuation { gate = $0 }
            isWaiting = false
        }
        return await BoardCoverRenderer.render(board: board, model: model, linkPreviewFiles: files)
    }

    func release() {
        holdsRenders = false
        gate?.resume()
        gate = nil
    }
}

/// A capa dos murais, conferida pelos pixels da imagem desenhada e pelo estado do serviço: o que aparece, que
/// miniaturas são aquecidas, quando a capa é desenhada de novo e o que vai para o disco.
@Suite("Capas dos murais")
@MainActor
struct BoardCoverTests {
    private static let photoColor = RenderedPixel(red: 0.85, green: 0.12, blue: 0.10, alpha: 1)
    /// `Theme.canvas` no claro.
    private static let canvasLight = RenderedPixel(red: 0.895, green: 0.902, blue: 0.914, alpha: 1)
    /// `Theme.sticky(.yellow)` e `Theme.sticky(.pink)`.
    private static let yellow = RenderedPixel(red: 1.00, green: 0.93, blue: 0.62, alpha: 1)
    private static let pink = RenderedPixel(red: 0.99, green: 0.84, blue: 0.88, alpha: 1)
    private static let red = RenderedPixel(red: 0.90, green: 0.05, blue: 0.05, alpha: 1)

    // MARK: Desenho

    @Test("Um post-it amarelo aparece amarelo no centro da capa, reduzido, e os cantos são o cinza do mural claro")
    func stickyIsYellowAndCornersAreCanvas() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeModel(Board(items: [Self.sticky(.yellow)]), in: directory)

        let image = try #require(await BoardCoverRenderer.render(board: model.board, model: model, linkPreviewFiles: nil))

        // 2 pixels por ponto: a capa de 320 × 200 pontos tem 640 × 400 pixels.
        #expect(image.width == 640 && image.height == 400, "\(image.width) × \(image.height)")
        // Um cartão só, de 110 × 110, vai a 0,6 e fica no meio: ocupa de 254 a 386 pixels na horizontal.
        let center = try Self.pixel(of: image, x: 320, y: 200)
        #expect(center.isClose(to: Self.yellow), "centro: \(center); esperado \(Self.yellow)")
        let beside = try Self.pixel(of: image, x: 236, y: 200)
        #expect(beside.isClose(to: Self.canvasLight), "o post-it passou de 254: \(beside)")
        for (x, y) in [(2, 2), (637, 2), (2, 397), (637, 397)] {
            let corner = try Self.pixel(of: image, x: x, y: y)
            #expect(corner.isClose(to: Self.canvasLight), "canto \(x), \(y): \(corner); esperado \(Self.canvasLight)")
        }
    }

    @Test("A capa é sempre clara, mesmo desenhada sob a aparência escura")
    func coverIsLightUnderDarkAppearance() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeModel(Board(items: [Self.sticky(.yellow)]), in: directory)
        let layout = BoardCoverLayout.make(for: model.board, coverWidth: 320, coverHeight: 200)
        let renderer = ImageRenderer(content: BoardCoverView(layout: layout, model: model).environment(\.colorScheme, .dark))
        renderer.scale = 2

        let image = try #require(renderer.cgImage)

        let corner = try Self.pixel(of: image, x: 2, y: 2)
        #expect(corner.isClose(to: Self.canvasLight), "o fundo seguiu a aparência escura: \(corner)")
    }

    @Test("A foto sai com a própria cor, e não com o cinza de carregamento: as miniaturas são aquecidas antes do desenho")
    func photoIsWarmedBeforeDrawing() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try makePhotoModel(in: directory.appendingPathComponent("Com", isDirectory: true))

        let image = try #require(await BoardCoverRenderer.render(board: model.board, model: model, linkPreviewFiles: nil))

        // A foto (150 × 190) vai a 0,6 e fica no meio da capa.
        let center = try Self.pixel(of: image, x: 320, y: 200)
        #expect(center.isClose(to: Self.photoColor), "centro: \(center); esperado \(Self.photoColor)")

        // Controle: sem aquecer o cache, o `ImageRenderer` desenha o quadro cinza e a comparação acima distingue os casos.
        let cold = try makePhotoModel(in: directory.appendingPathComponent("Sem", isDirectory: true))
        let layout = BoardCoverLayout.make(for: cold.board, coverWidth: 320, coverHeight: 200)
        let renderer = ImageRenderer(content: BoardCoverView(layout: layout, model: cold))
        renderer.scale = 2
        let coldImage = try #require(renderer.cgImage)
        let coldCenter = try Self.pixel(of: coldImage, x: 320, y: 200)
        #expect(!coldCenter.isClose(to: Self.photoColor, tolerance: 0.2), "a foto apareceu sem o aquecimento: \(coldCenter)")
    }

    // MARK: Pedidos de miniatura

    @Test("Os pedidos de miniatura são os que os cartões fariam: foto 640, link 480 e 64, música 480, pasta 240; sem repetidos")
    func thumbnailRequestsMatchWhatTheCardsAsk() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(directory: directory.appendingPathComponent("Pacote", isDirectory: true))
        let previews = LinkPreviewFiles(directory: directory.appendingPathComponent("Previas", isDirectory: true))
        let png = try Self.solidPNG(width: 200, height: 120, color: Self.photoColor)
        let icon = try Self.solidPNG(width: 64, height: 64, color: Self.red)
        let linkFiles = try previews.store(imageData: png, iconData: icon, for: UUID())
        let folderLinkFiles = try previews.store(imageData: png, iconData: nil, for: UUID())
        let artworkFiles = try previews.store(imageData: png, iconData: nil, for: UUID())
        let linkImage = try #require(linkFiles.image)
        let linkIcon = try #require(linkFiles.icon)
        let folderLinkImage = try #require(folderLinkFiles.image)
        let artwork = try #require(artworkFiles.image)

        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func item(
            _ kind: ItemKind, _ title: String, file: String? = nil, parent: UUID? = nil, order: Double = 0, link: LinkInfo? = nil,
            music: MusicSnapshot? = nil
        ) -> BoardItem {
            BoardItem(
                kind: kind, title: title, createdAt: base.addingTimeInterval(order), parentID: parent, fileName: file, link: link,
                music: music)
        }
        let url = URL(string: "https://apple.com")!
        let folderA = item(.folder, "Pasta A")
        let folderB = item(.folder, "Pasta B")
        let items: [BoardItem] = [
            item(.image, "Foto", file: "foto.png"),
            item(.video, "Vídeo", file: "clip.mov"),
            item(.pdf, "PDF", file: "doc.pdf"),
            item(.sticky, "Post-it"),
            item(.text, "Nota"),
            item(.checklist, "Lista"),
            item(.link, "Link", link: LinkInfo(url: url, previewImageFile: linkImage, iconFile: linkIcon)),
            // Os mesmos arquivos de outro cartão: o mesmo pedido, uma vez só.
            item(.link, "Outro link", link: LinkInfo(url: url, previewImageFile: linkImage, iconFile: linkIcon)),
            // Os arquivos não estão na pasta de prévias: o cartão fica no monograma e não pede nada.
            item(.link, "Link sem arquivos", link: LinkInfo(url: url, previewImageFile: "sumiu.jpg", iconFile: "sumiu.png")),
            item(.music, "Álbum", music: MusicSnapshot(kind: .album, title: "Álbum", artworkFile: artwork)),
            item(.music, "Álbum sem capa", music: MusicSnapshot(kind: .album, title: "Álbum sem capa", artworkFile: "sumiu.jpg")),
            folderA,
            folderB,
            // Pasta A: só os três mais recentes espiam; o mais antigo fica de fora. A mesma foto da raiz, em outro tamanho.
            item(.image, "Antiga", file: "antiga.png", parent: folderA.id, order: 1),
            item(.image, "Foto de novo", file: "foto.png", parent: folderA.id, order: 2),
            item(.sticky, "Post-it da pasta", parent: folderA.id, order: 3),
            item(.link, "Link da pasta", parent: folderA.id, order: 4, link: LinkInfo(url: url, previewImageFile: folderLinkImage)),
            // Pasta B: vídeo, PDF e música com capa.
            item(.video, "Vídeo da pasta", file: "clip2.mov", parent: folderB.id, order: 1),
            item(.pdf, "PDF da pasta", file: "doc2.pdf", parent: folderB.id, order: 2),
            item(
                .music, "Álbum da pasta", parent: folderB.id, order: 3, music: MusicSnapshot(kind: .album, title: "A", artworkFile: artwork)
            ),
        ]
        let board = Board(items: items)
        let model = BoardModel(board: board, store: store, persistence: .deferred)
        let layout = BoardCoverLayout.make(for: board, coverWidth: 320, coverHeight: 200, maximumItems: 120)

        let requests = BoardCoverRenderer.thumbnailRequests(for: layout, model: model, linkPreviewFiles: previews)

        func media(_ name: String, _ kind: ItemKind, _ size: Int) -> ThumbnailRequest {
            ThumbnailRequest(url: store.itemsDirectory.appendingPathComponent(name), kind: kind, maxPixelSize: size)
        }
        func preview(_ name: String, _ size: Int) -> ThumbnailRequest {
            ThumbnailRequest(url: previews.directory.appendingPathComponent(name, isDirectory: false), kind: .image, maxPixelSize: size)
        }
        let expected = [
            media("foto.png", .image, 640),
            media("clip.mov", .video, 640),
            media("doc.pdf", .pdf, 640),
            preview(linkImage, 480),
            preview(linkIcon, 64),
            preview(artwork, 480),
            media("foto.png", .image, 240),
            preview(folderLinkImage, 240),
            media("clip2.mov", .video, 240),
            media("doc2.pdf", .pdf, 240),
            preview(artwork, 240),
        ]
        #expect(requests == expected)
        #expect(Set(requests).count == requests.count, "há pedidos repetidos")
    }

    @Test("Sem a pasta de prévias, só foto, vídeo e PDF pedem miniatura, e um post-it sozinho não pede nenhuma")
    func thumbnailRequestsWithoutPreviewFolder() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BoardStore(directory: directory.appendingPathComponent("Pacote", isDirectory: true))
        let link = BoardItem(kind: .link, title: "Link", link: LinkInfo(url: URL(string: "https://apple.com")!, previewImageFile: "a.jpg"))
        let photo = BoardItem(kind: .image, title: "Foto", fileName: "foto.png")
        func requests(_ items: [BoardItem]) -> [ThumbnailRequest] {
            let board = Board(items: items)
            let model = BoardModel(board: board, store: store, persistence: .deferred)
            let layout = BoardCoverLayout.make(for: board, coverWidth: 320, coverHeight: 200)
            return BoardCoverRenderer.thumbnailRequests(for: layout, model: model, linkPreviewFiles: nil)
        }

        #expect(requests([Self.sticky(.yellow)]).isEmpty)
        #expect(
            requests([link, photo]) == [
                ThumbnailRequest(url: store.itemsDirectory.appendingPathComponent("foto.png"), kind: .image, maxPixelSize: 640)
            ])
    }

    // MARK: Serviço, mural fechado

    @Test("Mural fechado: pedir desenha e grava a capa com a revisão do mural; pedir de novo, ou reabrir o app, não desenha")
    func closedBoardIsDrawnOnceAndStored() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let entry = try await makeBoard("Obra", board: Board(items: [Self.sticky(.yellow)]), revision: 3, in: fixture)
        let id = entry.manifest.id
        let probe = CoverRenderProbe()
        let service = makeService(fixture, probe: probe)

        service.request([entry])
        await service.waitUntilIdle()

        let image = try #require(service.images[id])
        #expect(image.width == 640 && image.height == 400)
        let center = try Self.pixel(of: image, x: 320, y: 200)
        #expect(center.isClose(to: Self.yellow), "\(center)")
        #expect(fixture.files.latest(for: id)?.revision == 3, "a capa deve levar a revisão do mural")
        #expect(probe.calls == 1)

        service.request([entry])
        await service.waitUntilIdle()
        #expect(probe.calls == 1, "a capa da mesma revisão não é desenhada de novo")

        // App reaberto: a memória está vazia, mas a capa em disco confere e basta carregá-la.
        let reopenedProbe = CoverRenderProbe()
        let reopened = makeService(fixture, probe: reopenedProbe)
        reopened.request([entry])
        await reopened.waitUntilIdle()
        let loaded = try #require(reopened.images[id])
        let loadedCenter = try Self.pixel(of: loaded, x: 320, y: 200)
        #expect(loadedCenter.isClose(to: Self.yellow, tolerance: 0.06), "\(loadedCenter)")
        #expect(reopenedProbe.calls == 0, "a capa gravada não precisa ser desenhada")
    }

    @Test("O rascunho de exemplo também ganha capa")
    func welcomeDraftGetsACover() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        _ = try await fixture.library.bootstrap()
        let entries = try await fixture.library.listReport().entries
        let draft = try #require(entries.first { isDraft($0.route) })
        let probe = CoverRenderProbe()
        let service = makeService(fixture, probe: probe)

        service.request([draft])
        await service.waitUntilIdle()

        #expect(service.images[draft.manifest.id] != nil)
        #expect(fixture.files.latest(for: draft.manifest.id)?.revision == draft.manifest.contentRevision)
        #expect(probe.drawnBoards.first?.items.isEmpty == false, "o rascunho tem cartões")
    }

    @Test("Capa velha: aparece primeiro, a nova é desenhada uma vez e só a revisão nova fica no disco")
    func oldCoverShowsFirstThenIsRedrawn() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let entry = try await makeBoard("Obra", board: Board(items: [Self.sticky(.yellow)]), revision: 2, in: fixture)
        let id = entry.manifest.id
        try fixture.files.store(try Self.solidImage(width: 640, height: 400, color: Self.red), for: id, revision: 1)
        let probe = CoverRenderProbe()
        probe.holdsRenders = true
        let service = makeService(fixture, probe: probe)

        service.request([entry])
        try await waitUntil { probe.isWaiting && service.images[id] != nil }
        let old = try Self.pixel(of: try #require(service.images[id]), x: 320, y: 200)
        #expect(old.isClose(to: Self.red, tolerance: 0.1), "enquanto a nova não sai, aparece a velha: \(old)")

        probe.release()
        await service.waitUntilIdle()

        #expect(probe.calls == 1)
        let fresh = try Self.pixel(of: try #require(service.images[id]), x: 320, y: 200)
        #expect(fresh.isClose(to: Self.yellow), "depois, a nova: \(fresh)")
        #expect(fixture.files.latest(for: id)?.revision == 2)
        #expect(try contents(of: fixture.files.directory).count == 1, "a revisão 1 devia ter sido apagada")
    }

    @Test("Um pedido novo substitui o que ainda esperava na fila; a capa em andamento termina")
    func newRequestReplacesWaitingEntries() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let first = try await makeBoard("A", revision: 1, in: fixture)
        let second = try await makeBoard("B", revision: 1, in: fixture)
        let third = try await makeBoard("C", revision: 1, in: fixture)
        let probe = CoverRenderProbe()
        probe.holdsRenders = true
        let service = makeService(fixture, probe: probe)

        service.request([first, second, third])
        try await waitUntil { probe.isWaiting }
        service.request([third])
        probe.release()
        await service.waitUntilIdle()

        #expect(probe.calls == 2)
        #expect(Set(service.images.keys) == [first.manifest.id, third.manifest.id])
    }

    @Test("Passando do limite, saem da memória as capas menos recentes que o pedido não inclui; o disco as devolve sem desenhar")
    func memoryLimitDropsLeastRecentOutsideTheRequest() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var entries: [BoardLibraryEntry] = []
        for name in ["A", "B", "C", "D"] {
            entries.append(try await makeBoard(name, revision: 1, in: fixture))
        }
        let probe = CoverRenderProbe()
        let service = makeService(fixture, probe: probe, memoryLimit: 2)

        service.request(entries)
        await service.waitUntilIdle()
        #expect(service.images.count == 4, "todas estão no pedido: nenhuma sai")

        service.request([entries[3]])
        #expect(Set(service.images.keys) == [entries[2].manifest.id, entries[3].manifest.id])

        service.request([entries[0]])
        await service.waitUntilIdle()
        #expect(service.images[entries[0].manifest.id] != nil)
        #expect(service.images.count == 2)
        #expect(probe.calls == 4, "a capa dispensada voltou do disco, sem novo desenho")
    }

    // MARK: Serviço, mural aberto

    @Test("Mural aberto: desenha do modelo vivo, só de novo se mudou, e nada vai para o disco")
    func liveBoardIsDrawnFromTheModelAndNeverStored() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        // No disco, um post-it rosa; no modelo vivo, um amarelo ainda não gravado.
        let entry = try await makeBoard("Obra", board: Board(items: [Self.sticky(.pink)]), revision: 1, in: fixture)
        let id = entry.manifest.id
        let package = try await fixture.library.repository(for: entry.route).packageURL(for: id)
        let model = BoardModel(
            board: Board(items: [Self.sticky(.yellow)]), store: BoardStore(directory: package), persistence: .deferred)
        let probe = CoverRenderProbe()
        let service = makeService(fixture, probe: probe, live: [LiveBoard(id: id, model: model)])

        service.request([entry])
        await service.waitUntilIdle()
        let center = try Self.pixel(of: try #require(service.images[id]), x: 320, y: 200)
        #expect(center.isClose(to: Self.yellow), "a capa devia vir do modelo vivo, não do disco: \(center)")
        #expect(probe.calls == 1)

        service.request([entry])
        await service.waitUntilIdle()
        #expect(probe.calls == 1, "nada mudou: não desenha de novo")

        model.createSticky()
        service.request([entry])
        await service.waitUntilIdle()
        #expect(probe.calls == 2, "o mural mudou: desenha de novo")
        #expect(probe.drawnBoards.last == model.board)

        #expect(fixture.files.latest(for: id) == nil, "a capa do mural aberto não é gravada")
        #expect(try contents(of: fixture.files.directory).isEmpty)
    }

    // MARK: Serviço, atualização e limpeza

    @Test("Atualizar grava a revisão dada e mostra a capa; limpar apaga do disco e da memória quem saiu da lista")
    func refreshStoresTheGivenRevisionAndSweepRemovesTheRest() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let directory = fixture.root.appendingPathComponent("Pacotes", isDirectory: true)
        let stays = BoardID()
        let leaves = BoardID()
        let probe = CoverRenderProbe()
        let service = makeService(fixture, probe: probe)

        for (id, revision) in [(stays, 4), (leaves, 9)] {
            let model = makeModel(Board(items: [Self.sticky(.yellow)]), in: directory.appendingPathComponent(id.description))
            await service.refresh(board: model.board, model: model, boardID: id, revision: revision)
        }

        #expect(service.images.count == 2)
        #expect(fixture.files.latest(for: stays)?.revision == 4)
        #expect(fixture.files.latest(for: leaves)?.revision == 9)
        let center = try Self.pixel(of: try #require(service.images[leaves]), x: 320, y: 200)
        #expect(center.isClose(to: Self.yellow), "\(center)")

        service.sweep(keeping: [stays])
        await service.waitUntilIdle()

        #expect(Set(service.images.keys) == [stays])
        #expect(fixture.files.latest(for: leaves) == nil)
        #expect(fixture.files.latest(for: stays)?.revision == 4)
    }

    // MARK: Exemplo para ver

    @Test("Desenha a capa de um mural com foto, post-its, nota, lista, link, música, lembrete, pasta e texto livre, para ser vista")
    func attachesASampleCover() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (model, previews) = try makeShowcase(in: directory)

        let image = try #require(
            await BoardCoverRenderer.render(board: model.board, model: model, linkPreviewFiles: previews))

        #expect(image.width == 640 && image.height == 400)
        let png = try Self.pngData(of: image)
        Attachment.record(png, named: "capa-exemplo.png")
    }

    // MARK: Apoio

    private struct Fixture {
        let root: URL
        let library: BoardLibrary
        let files: BoardCoverFiles
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MuralCover-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFixture() throws -> Fixture {
        let root = try makeDirectory()
        // Mural excluído nos testes é apagado, não vai para o Lixo de quem roda os testes.
        let library = BoardLibrary(
            rootDirectory: root.appendingPathComponent("Biblioteca", isDirectory: true),
            discardPackage: { try FileManager.default.removeItem(at: $0) })
        return Fixture(
            root: root, library: library, files: BoardCoverFiles(directory: root.appendingPathComponent("Capas", isDirectory: true)))
    }

    private func makeService(
        _ fixture: Fixture, probe: CoverRenderProbe, live: [LiveBoard] = [], memoryLimit: Int = 30
    ) -> BoardCoverService {
        BoardCoverService(
            library: fixture.library, files: fixture.files, liveBoards: { live }, linkPreviewFiles: { _ in nil },
            render: probe.render, memoryLimit: memoryLimit)
    }

    /// Um modelo sobre uma pasta de pacote, sem gravar nada.
    private func makeModel(_ board: Board, in directory: URL) -> BoardModel {
        BoardModel(
            board: board, store: BoardStore(directory: directory.appendingPathComponent("Pacote", isDirectory: true)),
            persistence: .deferred)
    }

    /// Um modelo com uma foto de cor forte importada de verdade, na pasta de itens do pacote.
    private func makePhotoModel(in directory: URL) throws -> BoardModel {
        let model = BoardModel(store: BoardStore(directory: directory), seedIfEmpty: false)
        let data = try Self.solidPNG(width: 300, height: 400, color: Self.photoColor)
        try #require(model.importData(data, fileExtension: "png", kind: .image, title: "Foto") != nil)
        return model
    }

    private static func sticky(_ color: StickyColor, text: String = "Oi") -> BoardItem {
        BoardItem(kind: .sticky, title: text, position: BoardPoint(x: 100, y: 100), text: text, stickyColor: color)
    }

    /// Cria o mural na biblioteca, grava `board` na revisão dada e devolve a entrada que a listagem mostra.
    private func makeBoard(_ name: String, board: Board = Board(), revision: Int, in fixture: Fixture) async throws -> BoardLibraryEntry {
        let route = try await fixture.library.createNamedBoard(name)
        let snapshot = try #require(try await fixture.library.open(route))
        var manifest = snapshot.manifest
        manifest.contentRevision = revision
        let repository = try await fixture.library.repository(for: route)
        try await repository.save(BoardRepositorySnapshot(manifest: manifest, board: board, workspace: snapshot.workspace))
        let entries = try await fixture.library.listSaved()
        return try #require(entries.first { $0.route == route })
    }

    private func isDraft(_ route: BoardRoute) -> Bool {
        if case .welcomeDraft = route { return true }
        return false
    }

    private func contents(of directory: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    private func waitUntil(timeout: Duration = .seconds(10), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            try #require(ContinuousClock.now < deadline, "a condição não se cumpriu a tempo")
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: Imagens

    /// A cor de um pixel da imagem (sRGB, 0 a 1), contado a partir do canto superior esquerdo.
    private static func pixel(of image: CGImage, x: Int, y: Int) throws -> RenderedPixel {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var bytes = [UInt8](repeating: 0, count: 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            // O CGContext conta de baixo para cima: a imagem é deslocada para o pixel pedido cair em (0, 0).
            let height = CGFloat(image.height)
            context.draw(image, in: CGRect(x: -CGFloat(x), y: CGFloat(y) + 1 - height, width: CGFloat(image.width), height: height))
            return true
        }
        try #require(drawn)
        return RenderedPixel(
            red: Double(bytes[0]) / 255, green: Double(bytes[1]) / 255, blue: Double(bytes[2]) / 255, alpha: Double(bytes[3]) / 255)
    }

    private static func solidImage(width: Int, height: Int, color: RenderedPixel) throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    private static func solidPNG(width: Int, height: Int, color: RenderedPixel) throws -> Data {
        try pngData(of: solidImage(width: width, height: height, color: color))
    }

    /// Degradê diagonal, para as fotos do exemplo não serem lisas.
    private static func gradientPNG(
        width: Int, height: Int, from start: (Double, Double, Double), to end: (Double, Double, Double)
    ) throws -> Data {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let colors =
            [
                CGColor(srgbRed: start.0, green: start.1, blue: start.2, alpha: 1),
                CGColor(srgbRed: end.0, green: end.1, blue: end.2, alpha: 1),
            ] as CFArray
        let gradient = try #require(CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]))
        context.drawLinearGradient(
            gradient, start: CGPoint(x: 0, y: CGFloat(height)), end: CGPoint(x: CGFloat(width), y: 0), options: [])
        return try pngData(of: try #require(context.makeImage()))
    }

    private static func pngData(of image: CGImage) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }

    // MARK: Mural de exemplo

    /// O mural de exemplo do domínio, mais fotos (soltas e na pasta que espia), links com e sem imagem, música, lembrete
    /// e um texto livre. As imagens são geradas na hora.
    private func makeShowcase(in directory: URL) throws -> (BoardModel, LinkPreviewFiles) {
        let store = BoardStore(directory: directory.appendingPathComponent("Pacote", isDirectory: true))
        try FileManager.default.createDirectory(at: store.itemsDirectory, withIntermediateDirectories: true)
        let previews = LinkPreviewFiles(directory: directory.appendingPathComponent("Previas", isDirectory: true))
        var board = SampleBoard.make()
        let cottage = try #require(board.rootItems.first { $0.title == "The Cottage" })
        let later = Date.now.addingTimeInterval(60)

        func photo(
            _ title: String, from start: (Double, Double, Double), to end: (Double, Double, Double), size: (Int, Int),
            at position: BoardPoint = .zero, parent: UUID? = nil, order: Double = 0
        ) throws -> BoardItem {
            let name = "\(UUID().uuidString).png"
            try Self.gradientPNG(width: size.0, height: size.1, from: start, to: end).write(
                to: store.itemsDirectory.appendingPathComponent(name))
            return BoardItem(
                kind: .image, title: title, createdAt: later.addingTimeInterval(order), parentID: parent, position: position, fileName: name
            )
        }
        board.add(try photo("Terracota", from: (0.93, 0.42, 0.33), to: (0.45, 0.22, 0.16), size: (600, 900), at: BoardPoint(x: 620, y: 80)))
        board.add(
            try photo("Carvalho", from: (0.80, 0.62, 0.42), to: (0.30, 0.20, 0.12), size: (900, 1_200), at: BoardPoint(x: 620, y: 290)))
        // Três fotos na pasta "The Cottage": são as mais recentes, então saem em leque pela borda dela.
        for (index, colors) in [
            ((0.93, 0.42, 0.33), (0.45, 0.22, 0.16)), ((0.80, 0.62, 0.42), (0.30, 0.20, 0.12)), ((0.35, 0.55, 0.75), (0.10, 0.20, 0.35)),
        ].enumerated() {
            board.add(
                try photo("Detalhe \(index)", from: colors.0, to: colors.1, size: (600, 800), parent: cottage.id, order: Double(index)))
        }

        let linkID = UUID()
        let linkFiles = try previews.store(
            imageData: Self.gradientPNG(width: 1_200, height: 630, from: (0.29, 0.31, 0.88), to: (0.30, 0.78, 0.90)),
            iconData: Self.gradientPNG(width: 64, height: 64, from: (0.10, 0.45, 0.95), to: (0.30, 0.30, 0.75)), for: linkID)
        board.add(
            BoardItem(
                id: linkID, kind: .link, title: "Human Interface Guidelines", position: BoardPoint(x: 800, y: 80),
                link: LinkInfo(
                    url: URL(string: "https://developer.apple.com/design/human-interface-guidelines")!, siteName: "Apple Developer",
                    summary: "Princípios, padrões e componentes para criar apps com aparência e comportamento naturais.",
                    previewImageFile: linkFiles.image, iconFile: linkFiles.icon, preview: .ready(fetchedAt: .now))))
        board.add(
            BoardItem(
                kind: .link, title: "1Password", position: BoardPoint(x: 800, y: 290),
                link: LinkInfo(url: URL(string: "https://www.1password.com/features")!, summary: "Um cofre para senhas, cartões e notas.")))

        let artwork = try previews.store(
            imageData: Self.gradientPNG(width: 600, height: 600, from: (0.12, 0.23, 0.37), to: (0.85, 0.55, 0.25)), iconData: nil,
            for: UUID())
        board.add(
            BoardItem(
                kind: .music, title: "Abbey Road", position: BoardPoint(x: 980, y: 80),
                music: MusicSnapshot(
                    kind: .album, title: "Abbey Road", subtitle: "The Beatles", artworkFile: artwork.image, backgroundHex: "#1f3a5f",
                    primaryTextHex: "#ffffff", secondaryTextHex: "#c9d6e8", trackCount: 17)))
        board.add(
            BoardItem(
                kind: .reminder, title: "Ligar para o marceneiro", position: BoardPoint(x: 980, y: 310),
                reminder: ReminderSnapshot(
                    identifier: "exemplo", title: "Ligar para o marceneiro", dueDate: later, dueHasTime: true, listTitle: "Obra",
                    listColorHex: "#ff9500")))
        board.add(BoardFreeText(text: "Ideias para a sala de estar", position: BoardPoint(x: 620, y: 520)))

        return (BoardModel(board: board, store: store, persistence: .deferred), previews)
    }
}

extension RenderedPixel {
    /// Opaco e a menos de `tolerance` de `other` em cada canal.
    fileprivate func isClose(to other: RenderedPixel, tolerance: Double = 0.04) -> Bool {
        alpha > 0.99 && abs(red - other.red) <= tolerance && abs(green - other.green) <= tolerance
            && abs(blue - other.blue) <= tolerance
    }
}
