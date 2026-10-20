import CoreGraphics
import Foundation
import MuralKit
import SwiftUI
import Testing

@testable import Mural

@Suite("Sessões de mural por janela")
@MainActor
struct BoardWindowSessionTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralWindowSession-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeReady(_ session: BoardWindowSession) async throws {
        await session.load()
        let metrics = CanvasScrollMetrics(
            contentOffset: .zero,
            containerSize: CGSize(width: 900, height: 700),
            contentSize: CGSize(width: 3_400, height: 2_800))
        session.restoreCanvas(boardID: session.boardID, generation: session.generation, metrics: metrics)
        let center = session.workspace.canvas.logicalCenter.map { CGPoint(x: $0.x, y: $0.y) }
        let target =
            center.map {
                CanvasWorkspaceMath.targetOffset(
                    logicalCenter: $0,
                    zoom: session.zoom.zoom,
                    viewport: metrics.containerSize,
                    contentSize: metrics.contentSize,
                    contentInsets: metrics.contentInsets)
            } ?? .zero
        let reached = CanvasScrollMetrics(
            contentOffset: target,
            containerSize: metrics.containerSize,
            contentSize: metrics.contentSize,
            contentInsets: metrics.contentInsets)
        for _ in 0..<3 where session.restorationPhase != .ready {
            session.restoreCanvas(boardID: session.boardID, generation: session.generation, metrics: reached)
        }
        #expect(session.restorationPhase == .ready)
    }

    @Test("A, B e A mantêm conteúdo, filtro e canvas isolados após autosave")
    func sessionsRoundTripThroughNewRegistry() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let routeA = try await library.createNamedBoard("A")
        let routeB = try await library.createNamedBoard("B")
        let registry = BoardSessionRegistry(library: library)
        let sessionA = BoardWindowSession(route: routeA, registry: registry)
        let sessionB = BoardWindowSession(route: routeB, registry: registry)
        try await makeReady(sessionA)
        try await makeReady(sessionB)

        let itemA = try #require(sessionA.model?.importText("conteúdo A"))
        sessionA.setNavigation(path: [], filter: .notes)
        let canvasA = CanvasWorkspaceState(
            confirmedZoom: 1.25,
            logicalCenter: BoardPoint(x: 920, y: 540))
        sessionA.zoom.configure(workspace: canvasA)
        sessionA.zoom.viewport = CGSize(width: 900, height: 700)
        sessionA.zoom.scrollOffset = CanvasWorkspaceMath.targetOffset(
            logicalCenter: CGPoint(x: 920, y: 540),
            zoom: 1.25,
            viewport: sessionA.zoom.viewport,
            contentSize: CGSize(width: 3_400, height: 2_800))
        sessionA.recordCanvas(sessionA.zoom.confirmedWorkspace())
        sessionA.captureBoardIfNeeded()
        await sessionA.flushAndPrepareToLeave()
        #expect(!sessionA.isDirty)

        let itemB = try #require(sessionB.model?.importText("conteúdo B"))
        sessionB.captureBoardIfNeeded()
        await sessionB.flushAndPrepareToLeave()
        #expect(itemA.id != itemB.id)

        // The registry is the single owner for an ID, so repeated opens share a
        // domain session while each window adapter remains independent.
        let first = try #require(await registry.open(routeA))
        let second = try #require(await registry.open(routeA))
        #expect(first === second)

        let reloadedLibrary = BoardLibrary(rootDirectory: directory)
        let reloadedRegistry = BoardSessionRegistry(library: reloadedLibrary)
        let reloadedA = BoardWindowSession(route: routeA, registry: reloadedRegistry)
        try await makeReady(reloadedA)
        #expect(reloadedA.model?.item(id: itemA.id)?.text == "conteúdo A")
        #expect(reloadedA.filter == .notes)
        #expect(reloadedA.workspace.canvas == sessionA.workspace.canvas)
        #expect(reloadedA.model?.item(id: itemB.id) == nil)
    }

    @Test("Path UUID e filtro fazem round-trip sem converter BoardID")
    func navigationRoundTripUsesItemUUID() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Navegação")
        let registry = BoardSessionRegistry(library: library)
        let session = BoardWindowSession(route: route, registry: registry)
        try await makeReady(session)
        let item = try #require(session.model?.importText("detalhe"))
        session.setNavigation(path: [.item(item.id)], filter: nil)
        session.captureBoardIfNeeded()
        await session.flushAndPrepareToLeave()

        let reloaded = BoardWindowSession(
            route: route,
            registry: BoardSessionRegistry(library: BoardLibrary(rootDirectory: directory)))
        try await makeReady(reloaded)
        #expect(reloaded.path == [.item(item.id)])
        #expect(reloaded.filter == nil)
    }

    @Test("Cem ciclos de persistência de canvas não acumulam drift")
    func canvasCyclesDoNotDriftInSession() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Canvas")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        try await makeReady(session)
        let expected = CanvasWorkspaceState(confirmedZoom: 1.1, logicalCenter: BoardPoint(x: 1_200, y: 980))
        session.zoom.configure(workspace: expected)
        session.zoom.viewport = CGSize(width: 900, height: 700)
        session.zoom.scrollOffset = CanvasWorkspaceMath.targetOffset(
            logicalCenter: CGPoint(x: 1_200, y: 980),
            zoom: 1.1,
            viewport: session.zoom.viewport,
            contentSize: CGSize(width: 3_400, height: 2_800))
        session.zoom.visibleRect = CGRect(origin: session.zoom.scrollOffset, size: session.zoom.viewport)
        for _ in 0..<100 {
            session.recordCanvas(session.zoom.confirmedWorkspace())
            session.captureBoardIfNeeded()
            await session.flushAndPrepareToLeave()
        }
        let center = session.workspace.canvas.logicalCenter
        #expect(center != nil)
        #expect(abs(center!.x - 1_200) <= 1)
        #expect(abs(center!.y - 980) <= 1)
    }

    @Test("Falha de flush mantém dirty e assets até o retry")
    func failedAutosaveRetriesWithoutDeletingAsset() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let initialLibrary = BoardLibrary(rootDirectory: directory)
        let route = try await initialLibrary.createNamedBoard("Falha")
        let failingLibrary = BoardLibrary(
            rootDirectory: directory,
            repositoryFaultInjection: BoardRepositoryFaultInjection(points: [.beforeSwap]))
        let session = BoardWindowSession(
            route: route,
            registry: BoardSessionRegistry(library: failingLibrary))
        try await makeReady(session)
        let item = try #require(
            session.model?.importData(
                Data([1, 2, 3]), fileExtension: "mov", kind: .video, title: "não perder"))
        let assetURL = try #require(session.model?.fileURL(for: item))
        session.captureBoardIfNeeded()
        await session.flushAndPrepareToLeave()
        #expect(session.isDirty)
        #expect(session.error?.contains("Não foi possível salvar o mural:") == true)
        #expect(FileManager.default.fileExists(atPath: assetURL.path))

        await session.flushAndPrepareToLeave()
        #expect(!session.isDirty)
        let reloaded = try #require(await failingLibrary.open(route))
        #expect(reloaded.board.item(id: item.id)?.title == "não perder")
        #expect(FileManager.default.fileExists(atPath: assetURL.path))
    }

    @Test("Falha ao apagar preserva o snapshot anterior e o asset")
    func failedDeleteKeepsPreviousSnapshotUntilRetry() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let initialLibrary = BoardLibrary(rootDirectory: directory)
        let route = try await initialLibrary.createNamedBoard("Apagar")
        let initialSession = BoardWindowSession(
            route: route,
            registry: BoardSessionRegistry(library: initialLibrary))
        try await makeReady(initialSession)
        let item = try #require(
            initialSession.model?.importData(
                Data([4, 5, 6]), fileExtension: "mov", kind: .video, title: "retido"))
        let assetURL = try #require(initialSession.model?.fileURL(for: item))
        initialSession.captureBoardIfNeeded()
        await initialSession.flushAndPrepareToLeave()
        #expect(!initialSession.isDirty)

        let failingLibrary = BoardLibrary(
            rootDirectory: directory,
            repositoryFaultInjection: BoardRepositoryFaultInjection(points: [.beforeSwap]))
        let session = BoardWindowSession(
            route: route,
            registry: BoardSessionRegistry(library: failingLibrary))
        try await makeReady(session)
        try #require(session.model?.item(id: item.id))
        session.model?.delete(item.id)
        session.captureBoardIfNeeded()
        await session.flushAndPrepareToLeave()
        #expect(session.isDirty)
        #expect(FileManager.default.fileExists(atPath: assetURL.path))
        let beforeRetry = try #require(await failingLibrary.open(route))
        #expect(beforeRetry.board.item(id: item.id) != nil)

        await session.flushAndPrepareToLeave()
        #expect(!session.isDirty)
        let afterRetry = try #require(await failingLibrary.open(route))
        #expect(afterRetry.board.item(id: item.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: assetURL.path))
    }

    @Test("Mutação de conteúdo durante restauração é autosalva")
    func contentMutationBeforeCanvasReadyPersists() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Antes do canvas")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        await session.load()
        #expect(session.restorationPhase == .awaitingLayout)
        let item = try #require(session.model?.importText("durante restauração"))
        session.captureBoardIfNeeded()
        await session.flushAndPrepareToLeave()

        let snapshot = try #require(await library.open(route))
        #expect(snapshot.board.item(id: item.id)?.text == "durante restauração")
        #expect(!session.isDirty)
    }

    @Test("Snapshot mais novo vence falha do flush bloqueado")
    func newerSnapshotSurvivesBlockedFlushFailure() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let initialLibrary = BoardLibrary(rootDirectory: directory)
        let route = try await initialLibrary.createNamedBoard("Sequência")
        let gate = BoardRepositoryFaultGate()
        let failingLibrary = BoardLibrary(
            rootDirectory: directory,
            repositoryFaultInjection: BoardRepositoryFaultInjection(points: [.beforeSwap], gate: gate))
        let session = BoardWindowSession(
            route: route,
            registry: BoardSessionRegistry(library: failingLibrary))
        try await makeReady(session)
        let item = try #require(session.model?.importText("snapshot 1"))
        session.captureBoardIfNeeded()

        let firstFlush = Task { await session.flushAndPrepareToLeave() }
        await gate.waitUntilReached()
        session.model?.setCaption("snapshot 2", for: item.id)
        session.captureBoardIfNeeded()
        await gate.release()
        await firstFlush.value

        #expect(session.isDirty)
        await session.flushAndPrepareToLeave()
        #expect(!session.isDirty)
        let snapshot = try #require(await failingLibrary.open(route))
        #expect(snapshot.board.item(id: item.id)?.text == "snapshot 2")
    }

    @Test("Posições de leitura usam âncora, fallback e limites reais")
    func readingPositionGeometryContracts() {
        let folderID = UUID()
        let firstID = UUID()
        let position = ReadingPosition.collectionSnapshot(
            folderID: folderID,
            visibleRect: CGRect(x: 0, y: 145, width: 800, height: 600),
            itemFrames: [
                (id: firstID, frame: CGRect(x: 0, y: 120, width: 300, height: 180)),
                (id: UUID(), frame: CGRect(x: 0, y: 330, width: 300, height: 180)),
            ])
        #expect(
            position
                == .collection(
                    folderID: folderID,
                    firstVisibleItemID: firstID,
                    relativeOffset: 25,
                    fallbackContentY: 145))
        #expect(
            ReadingPosition.collectionTargetY(
                position,
                itemFrame: CGRect(x: 0, y: 120, width: 300, height: 180),
                contentHeight: 1_000,
                viewportHeight: 400,
                contentInsetsTop: 20,
                contentInsetsBottom: 30) == 145)
        #expect(
            ReadingPosition.itemTargetY(
                .item(itemID: firstID, visibleContentY: -50),
                contentHeight: 1_000,
                viewportHeight: 400,
                contentInsetsTop: 20,
                contentInsetsBottom: 30) == -20)
    }

    @Test("PDF position clamps page, scale e ponto")
    func pdfPositionClampContract() {
        let itemID = UUID()
        let position = ReadingPosition.clampedPDF(
            itemID: itemID,
            pageIndex: 99,
            pageCount: 4,
            scale: 99,
            scaleRange: 0.5...3,
            pointInPage: BoardPoint(x: -10, y: 900),
            pageBounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        #expect(
            position
                == .pdf(
                    itemID: itemID,
                    pageIndex: 3,
                    scale: 3,
                    pointInPage: BoardPoint(x: 0, y: 792)))
    }

    @Test("Barreira inicial impede callback e libera captura depois do layout")
    func readingRestoreBarrierRejectsInitialCallback() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Leitura")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        try await makeReady(session)
        let item = try #require(session.model?.importText("texto"))
        let generation = session.generation
        _ = session.beginReadingRestore(for: item.id)
        session.recordReadingPosition(
            .item(itemID: item.id, visibleContentY: 400),
            boardID: session.boardID,
            generation: generation)
        #expect(session.readingPosition(for: item.id) == nil)
        session.finishReadingRestore(for: item.id)
        session.recordReadingPosition(
            .item(itemID: item.id, visibleContentY: 400),
            boardID: session.boardID,
            generation: generation)
        #expect(session.readingPosition(for: item.id) == .item(itemID: item.id, visibleContentY: 400))
    }

    @Test("Caption draft é gravado imediatamente no leave e reabre")
    func captionDraftCommitsWithoutDebounce() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Legenda")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        try await makeReady(session)
        let item = try #require(session.model?.importText("imagem"))
        session.setCaptionDraft("última tecla", for: item.id)
        await session.flushAndPrepareToLeave()
        let reloaded = BoardWindowSession(
            route: route,
            registry: BoardSessionRegistry(library: BoardLibrary(rootDirectory: directory)))
        await reloaded.load()
        #expect(reloaded.model?.item(id: item.id)?.text == "última tecla")
    }

    @Test("Reading position sobrevive A/B/A e novo registry")
    func readingPositionRoundTripThroughRegistry() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let routeA = try await library.createNamedBoard("A")
        let routeB = try await library.createNamedBoard("B")
        let registry = BoardSessionRegistry(library: library)
        let a = BoardWindowSession(route: routeA, registry: registry)
        let b = BoardWindowSession(route: routeB, registry: registry)
        try await makeReady(a)
        try await makeReady(b)
        let item = try #require(a.model?.importText("leitura A"))
        a.recordReadingPosition(
            .item(itemID: item.id, visibleContentY: 321),
            boardID: a.boardID,
            generation: a.generation)
        a.captureBoardIfNeeded()
        await a.flushAndPrepareToLeave()
        let itemB = try #require(b.model?.importText("B"))
        b.setCaptionDraft("não misturar", for: itemB.id)
        await b.flushAndPrepareToLeave()

        let reloaded = BoardWindowSession(
            route: routeA,
            registry: BoardSessionRegistry(library: BoardLibrary(rootDirectory: directory)))
        try await makeReady(reloaded)
        #expect(reloaded.readingPosition(for: item.id) == .item(itemID: item.id, visibleContentY: 321))
    }

    @Test("Exclusão remove path e reading position canônicos")
    func deletionPrunesWorkspaceState() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Prune")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        try await makeReady(session)
        let item = try #require(session.model?.importText("aberto"))
        session.setNavigation(path: [.item(item.id)], filter: nil)
        session.recordReadingPosition(
            .item(itemID: item.id, visibleContentY: 80),
            boardID: session.boardID,
            generation: session.generation)
        session.delete(item.id)
        #expect(session.path.isEmpty)
        #expect(session.readingPosition(for: item.id) == nil)
    }
}
