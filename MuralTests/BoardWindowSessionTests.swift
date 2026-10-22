import AppKit
import CoreGraphics
import Foundation
import MuralKit
import PDFKit
import StretchText
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
        session.restoreCanvas(boardID: session.boardID, generation: session.presentationGeneration, metrics: metrics)
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
            session.restoreCanvas(boardID: session.boardID, generation: session.presentationGeneration, metrics: reached)
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
        let first = try await registry.open(routeA)
        let second = try await registry.open(routeA)
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

    @Test("Restauração não reenvia o mesmo alvo enquanto aguarda a geometria")
    func canvasRestoreDoesNotReissueStableTarget() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Canvas não zero")
        let initial = BoardWindowSession(
            route: route,
            registry: BoardSessionRegistry(library: library))
        try await makeReady(initial)

        let expected = CanvasWorkspaceState(
            confirmedZoom: 1.75,
            logicalCenter: BoardPoint(x: 470, y: 440))
        let viewport = CGSize(width: 900, height: 700)
        let contentSize = CGSize(width: 3_400, height: 2_800)
        initial.zoom.configure(workspace: expected)
        initial.zoom.viewport = viewport
        initial.zoom.scrollOffset = CanvasWorkspaceMath.targetOffset(
            logicalCenter: CGPoint(x: 470, y: 440),
            zoom: 1.75,
            viewport: viewport,
            contentSize: contentSize)
        initial.zoom.visibleRect = CGRect(origin: initial.zoom.scrollOffset, size: viewport)
        initial.recordCanvas(initial.zoom.confirmedWorkspace())
        await initial.flushAndPrepareToLeave()

        let restored = BoardWindowSession(
            route: route,
            registry: BoardSessionRegistry(library: BoardLibrary(rootDirectory: directory)))
        await restored.load()
        let notYetReached = CanvasScrollMetrics(
            contentOffset: .zero,
            containerSize: viewport,
            contentSize: contentSize)

        restored.restoreCanvas(
            boardID: restored.boardID,
            generation: restored.presentationGeneration,
            metrics: notYetReached)
        let firstRequest = try #require(restored.zoom.scrollRequest)
        #expect(restored.restorationPhase == .applyingPosition)

        restored.restoreCanvas(
            boardID: restored.boardID,
            generation: restored.presentationGeneration,
            metrics: notYetReached)

        #expect(restored.zoom.scrollRequest == firstRequest)
        #expect(restored.restorationPhase == .applyingPosition)
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
        _ = try #require(session.model?.item(id: item.id))
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

    @Test("Coleção usa fallback ao excluir âncora e mantém o offset ao redimensionar")
    func collectionFallbackSurvivesAnchorRemovalAndResize() {
        let folderID = UUID()
        let anchorID = UUID()
        let saved = ReadingPosition.collection(
            folderID: folderID,
            firstVisibleItemID: anchorID,
            relativeOffset: 18,
            fallbackContentY: 640)
        let withAnchor = ReadingPosition.collectionTargetY(
            saved,
            itemFrame: CGRect(x: 0, y: 500, width: 300, height: 200),
            contentHeight: 2_000,
            viewportHeight: 700,
            contentInsetsTop: 70,
            contentInsetsBottom: 90)
        #expect(withAnchor == 518)
        let afterDeletion = ReadingPosition.collectionTargetY(
            saved,
            itemFrame: nil,
            contentHeight: 2_000,
            viewportHeight: 900,
            contentInsetsTop: 70,
            contentInsetsBottom: 90)
        #expect(afterDeletion == 640)
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
        let generation = session.presentationGeneration
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

    @Test("Callback de apresentação antiga não termina nem grava na apresentação nova")
    func staleReadingPresentationTokenIsIgnored() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Tokens")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        try await makeReady(session)
        let item = try #require(session.model?.importText("item"))
        let oldToken = session.readingPresentationToken(for: item.id)
        _ = session.beginReadingRestore(token: oldToken)
        #expect(session.finishReadingRestore(token: oldToken))
        session.recordReadingPosition(.item(itemID: item.id, visibleContentY: 120), token: oldToken)
        session.setNavigation(path: [.item(item.id)], filter: nil)
        let newToken = session.readingPresentationToken(for: item.id)
        #expect(oldToken != newToken)
        session.recordReadingPosition(.item(itemID: item.id, visibleContentY: 999), token: oldToken)
        #expect(session.readingPosition(for: item.id) == .item(itemID: item.id, visibleContentY: 120))
        _ = session.beginReadingRestore(token: newToken)
        #expect(!session.finishReadingRestore(token: oldToken))
        #expect(session.finishReadingRestore(token: newToken))
    }

    @Test("Finalizador captura antes de invalidar o token e persiste no flush")
    func finalizerRunsBeforeNavigationGenerationChanges() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Finalizador")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        try await makeReady(session)
        let item = try #require(session.model?.importText("PDF"))
        let token = session.readingPresentationToken(for: item.id)
        var didCaptureBeforeNavigation = false
        session.registerReadingFinalizer(for: token) {
            #expect(session.acceptsReadingPresentation(token))
            session.recordReadingPosition(
                .item(itemID: item.id, visibleContentY: 777), token: token)
            didCaptureBeforeNavigation = true
        }
        session.setNavigation(path: [], filter: nil)
        #expect(didCaptureBeforeNavigation)
        #expect(!session.acceptsReadingPresentation(token))
        await session.flushAndPrepareToLeave()

        let reloaded = BoardWindowSession(
            route: route,
            registry: BoardSessionRegistry(library: BoardLibrary(rootDirectory: directory)))
        try await makeReady(reloaded)
        #expect(reloaded.readingPosition(for: item.id) == .item(itemID: item.id, visibleContentY: 777))
    }

    @Test("PDF frame zero aguarda layout e saída imediata cancela o debounce")
    func pdfCoordinatorWaitsForLayoutAndPublishesBeforeInvalidate() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("PDF")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        try await makeReady(session)
        let item = try #require(session.model?.importText("PDF"))
        let token = session.readingPresentationToken(for: item.id)
        session.recordReadingPosition(
            .pdf(
                itemID: item.id,
                pageIndex: 0,
                scale: 1,
                pointInPage: BoardPoint(x: 36, y: 36)),
            token: token)
        let pdfData = try makeOnePagePDF()
        let document = try #require(PDFDocument(data: pdfData))
        let view = PDFView(frame: .zero)
        view.document = document
        let coordinator = PDFKitView.Coordinator(
            itemID: item.id,
            url: URL(fileURLWithPath: "/tmp/mural-test.pdf"),
            session: session)
        coordinator.install(on: view)
        // Frame zero is intentionally not enough to release the local barrier.
        session.recordReadingPosition(
            .item(itemID: item.id, visibleContentY: 1), token: token)
        #expect(session.readingPosition(for: item.id) != .item(itemID: item.id, visibleContentY: 1))

        view.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
        view.layoutSubtreeIfNeeded()
        coordinator.restoreDidChange(in: view)
        coordinator.restoreDidChange(in: view)
        let pageBeforeScroll = view.currentDestination?.page
        let scaleBeforeScroll = view.scaleFactor
        if let clipView = firstClipView(in: view) {
            clipView.setBoundsOrigin(CGPoint(x: 12, y: 14))
            coordinator.restoreDidChange(in: view)
            #expect(view.currentDestination?.page === pageBeforeScroll)
            #expect(abs(view.scaleFactor - scaleBeforeScroll) <= 0.01)
        }
        view.go(to: PDFDestination(page: try #require(document.page(at: 0)), at: CGPoint(x: 72, y: 72)))
        coordinator.restoreDidChange(in: view)
        coordinator.invalidate()
        #expect(coordinator.restoreCallbackCount >= 2)
        #expect(coordinator.observedClipView != nil)
        #expect(session.readingPosition(for: item.id) != nil)
        session.setNavigation(path: [], filter: nil)
        session.recordReadingPosition(
            .item(itemID: item.id, visibleContentY: 2), token: token)
        #expect(session.readingPosition(for: item.id) != .item(itemID: item.id, visibleContentY: 2))
    }

    @Test("PDF indisponível libera a barreira sem acessar uma página inexistente")
    func unavailablePDFCompletesRestoreSafely() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("PDF indisponível")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        try await makeReady(session)
        let item = try #require(session.model?.importText("PDF"))
        let token = session.readingPresentationToken(for: item.id)
        let view = PDFView(frame: CGRect(x: 0, y: 0, width: 640, height: 480))
        let coordinator = PDFKitView.Coordinator(
            itemID: item.id,
            url: URL(fileURLWithPath: "/tmp/mural-pdf-indisponivel.pdf"),
            session: session)

        coordinator.install(on: view)
        session.recordReadingPosition(
            .item(itemID: item.id, visibleContentY: 321), token: token)

        #expect(session.readingPosition(for: item.id) == .item(itemID: item.id, visibleContentY: 321))
        coordinator.invalidate()
        coordinator.invalidate()
    }

    @Test("Troca de URL encerra a apresentação anterior e registra a nova")
    func pdfCoordinatorRebindsPresentationWhenURLChanges() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Troca de PDF")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        try await makeReady(session)
        let item = try #require(session.model?.importText("PDF"))
        let document = PDFDocument(data: try makeOnePagePDF())
        let view = PDFView(frame: CGRect(x: 0, y: 0, width: 640, height: 480))
        view.document = document
        let firstURL = URL(fileURLWithPath: "/tmp/mural-primeiro.pdf")
        let secondURL = URL(fileURLWithPath: "/tmp/mural-segundo.pdf")
        let coordinator = PDFKitView.Coordinator(itemID: item.id, url: firstURL, session: session)
        coordinator.install(on: view)
        coordinator.restoreDidChange(in: view)

        #expect(coordinator.update(url: secondURL, in: view))
        view.document = PDFDocument(data: try makeOnePagePDF())
        coordinator.restore(in: view)
        coordinator.restoreDidChange(in: view)
        coordinator.invalidate()
        coordinator.invalidate()
        let token = session.readingPresentationToken(for: item.id)
        session.recordReadingPosition(
            .item(itemID: item.id, visibleContentY: 654), token: token)

        #expect(session.readingPosition(for: item.id) == .item(itemID: item.id, visibleContentY: 654))
    }

    @Test("Pedidos simultâneos de saída compartilham a mesma barreira de flush")
    func concurrentLeaveFlushesAreDeduplicated() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Flush único")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        try await makeReady(session)
        _ = try #require(session.model?.importText("conteúdo"))
        session.captureBoardIfNeeded()

        async let first: Void = session.flushAndPrepareToLeave()
        async let second: Void = session.flushAndPrepareToLeave()
        _ = await (first, second)

        #expect(!session.isDirty)
        #expect(session.error == nil)
    }

    private func makeOnePagePDF() throws -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
            let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private func firstClipView(in view: NSView) -> NSClipView? {
        if let clipView = view as? NSClipView { return clipView }
        for child in view.subviews {
            if let clipView = firstClipView(in: child) { return clipView }
        }
        return nil
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

    @Test("Draft de imagem falha sem perder texto e o retry persiste")
    func imageDraftSurvivesFlushFailureAndRetry() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let initialLibrary = BoardLibrary(rootDirectory: directory)
        let route = try await initialLibrary.createNamedBoard("Imagem")
        let initial = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: initialLibrary))
        try await makeReady(initial)
        let item = try #require(
            initial.model?.importData(
                Data([1, 2, 3]), fileExtension: "png", kind: .image, title: "imagem"))
        initial.captureBoardIfNeeded()
        await initial.flushAndPrepareToLeave()

        let failing = BoardLibrary(
            rootDirectory: directory,
            repositoryFaultInjection: BoardRepositoryFaultInjection(points: [.beforeSwap]))
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: failing))
        try await makeReady(session)
        session.setCaptionDraft("texto final", for: item.id)
        await session.flushAndPrepareToLeave()
        #expect(session.isDirty)
        #expect(session.captionDraft(for: item.id) == "texto final")
        await session.flushAndPrepareToLeave()
        #expect(!session.isDirty)
        let reloaded = try #require(await failing.open(route))
        #expect(reloaded.board.item(id: item.id)?.text == "texto final")
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
            generation: a.presentationGeneration)
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

    @Test("Parágrafos abertos voltam ao reabrir; texto editado volta tudo dobrado")
    func openStretchesRoundTrip() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Abertos")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        try await makeReady(session)
        let body = "Primeira frase. Segunda frase.\n\nOutro bloco. Com duas frases."
        let note = try #require(session.model?.importText(body, as: .text))
        let second = try #require(StretchID(path: [1]))
        session.recordOpenStretches([second], for: note.id, source: body)
        #expect(session.openStretchIDs(for: note.id, source: body) == [second])
        #expect(session.openStretchIDs(for: note.id, source: body + " Outra.").isEmpty)
        session.captureBoardIfNeeded()
        await session.flushAndPrepareToLeave()

        let reloaded = BoardWindowSession(
            route: route, registry: BoardSessionRegistry(library: BoardLibrary(rootDirectory: directory)))
        try await makeReady(reloaded)
        #expect(reloaded.openStretchIDs(for: note.id, source: body) == [second])

        reloaded.recordOpenStretches([], for: note.id, source: body)
        #expect(reloaded.workspace.openStretches[note.id] == nil)
    }

    @Test("Rascunho da nota vai para o mural ao concluir; sair da página também conclui")
    func noteDraftCommitsOnFinishAndOnLeave() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Edição")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        try await makeReady(session)
        let note = try #require(session.model?.importText("Corpo antigo. Com duas frases.", as: .text))

        session.beginEditing(note.id)
        #expect(session.editingItemID == note.id)
        session.setNoteDraft(NoteDraft(title: "Visita", text: "Corpo **novo**."), for: note.id)
        #expect(session.model?.item(id: note.id)?.text == "Corpo antigo. Com duas frases.", "rascunho não grava antes")
        session.finishEditing()
        #expect(session.editingItemID == nil)
        #expect(session.model?.item(id: note.id)?.title == "Visita")
        #expect(session.model?.item(id: note.id)?.text == "Corpo **novo**.")

        session.setNavigation(path: [.item(note.id)], filter: nil)
        session.beginEditing(note.id)
        session.setNoteDraft(NoteDraft(title: "Visita", text: "Saindo da página."), for: note.id)
        session.setNavigation(path: [], filter: nil)
        #expect(session.editingItemID == nil)
        #expect(session.model?.item(id: note.id)?.text == "Saindo da página.")
    }

    @Test("Fechar a janela no meio da edição grava o rascunho")
    func noteDraftSurvivesClose() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Fechar")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        try await makeReady(session)
        let sticky = try #require(session.model?.importText("Luz quente", as: .sticky))
        session.beginEditing(sticky.id)
        session.setNoteDraft(NoteDraft(text: "Luz quente em tudo", color: .green), for: sticky.id)
        await session.prepareToClose()

        let reloaded = BoardWindowSession(
            route: route, registry: BoardSessionRegistry(library: BoardLibrary(rootDirectory: directory)))
        try await makeReady(reloaded)
        let saved = try #require(reloaded.model?.item(id: sticky.id))
        #expect(saved.text == "Luz quente em tudo")
        #expect(saved.stickyColor == .green)
    }

    @Test("Só nota e post-it entram em edição; começar outra conclui a anterior")
    func editingSwitchesItems() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Troca")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        try await makeReady(session)
        let first = try #require(session.model?.importText("Primeira nota. Com duas frases.", as: .text))
        let second = try #require(session.model?.importText("Segunda nota. Com duas frases.", as: .text))
        let list = try #require(session.model?.importText("Compras\n- pão\n- leite", as: .checklist))

        session.beginEditing(list.id)
        #expect(session.editingItemID == nil)
        session.beginEditing(first.id)
        session.setNoteDraft(NoteDraft(title: "Primeira", text: "Editada."), for: first.id)
        session.beginEditing(second.id)
        #expect(session.editingItemID == second.id)
        #expect(session.model?.item(id: first.id)?.text == "Editada.")
    }

    @Test("Card novo abre editando; vazio ao concluir é descartado, com conteúdo fica")
    func createCardDiscardsBlank() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Novos")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        try await makeReady(session)

        let blank = try #require(session.createCard(.text))
        #expect(session.path == [.item(blank)])
        #expect(session.editingItemID == blank)
        session.finishEditing()
        #expect(session.model?.item(id: blank) == nil)
        #expect(session.path.isEmpty)

        let kept = try #require(session.createCard(.sticky))
        session.setNoteDraft(NoteDraft(text: "Luz quente", color: .pink), for: kept)
        session.setNavigation(path: [], filter: nil)
        let saved = try #require(session.model?.item(id: kept))
        #expect(saved.text == "Luz quente")
        #expect(saved.stickyColor == .pink)
        #expect(saved.parentID == nil)

        // Cartão que já existia não é apagado só por ficar vazio.
        session.beginEditing(kept)
        session.setNoteDraft(NoteDraft(text: "", color: .pink), for: kept)
        session.finishEditing()
        #expect(session.model?.item(id: kept) != nil)
    }

    @Test("Dentro de uma pasta, o card novo entra na pasta e abre por cima dela")
    func createCardInsideFolder() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let state = try await library.bootstrap()
        let session = BoardWindowSession(
            route: .welcomeDraft(state.stableWelcomeID), registry: BoardSessionRegistry(library: library))
        try await makeReady(session)
        let folder = try #require(session.model?.rootItems.first { $0.kind == .folder })
        session.setNavigation(path: [.collection(folder.id)], filter: nil)

        let note = try #require(session.createCard(.text))
        #expect(session.model?.item(id: note)?.parentID == folder.id)
        #expect(session.path == [.collection(folder.id), .item(note)])
        session.setNoteDraft(NoteDraft(title: "Na pasta", text: "Corpo."), for: note)
        session.setNavigation(path: [.collection(folder.id)], filter: nil)
        #expect(session.model?.children(of: folder.id).contains { $0.id == note } == true)
    }

    @Test("Pasta nova entra solta no mural, abre vazia e volta igual ao reabrir; dentro dela não há outra")
    func createFolderOpensIt() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Pastas")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        try await makeReady(session)
        #expect(session.acceptsNewFolder)

        let folderID = try #require(session.createFolder(named: "Referências"))
        let folder = try #require(session.model?.item(id: folderID))
        #expect(folder.kind == .folder)
        #expect(folder.parentID == nil)
        #expect(session.path == [.collection(folderID)])
        #expect(!session.acceptsNewFolder)
        #expect(session.createFolder(named: "Dentro") == nil)
        #expect(session.model?.rootItems.filter { $0.kind == .folder }.map(\.id) == [folderID])
        await session.flushAndPrepareToLeave()

        let reloaded = BoardWindowSession(
            route: route, registry: BoardSessionRegistry(library: BoardLibrary(rootDirectory: directory)))
        try await makeReady(reloaded)
        #expect(reloaded.model?.item(id: folderID)?.title == "Referências")
    }

    @Test("Seleção apaga vários cartões do mural de uma vez; a pasta leva o conteúdo e o resto fica")
    func deleteSelection() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Seleção")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        try await makeReady(session)
        let model = try #require(session.model)
        let kept = model.createSticky()
        let note = model.createNote()
        let folder = model.createFolder(named: "Caixa")
        let inside = model.createNote(into: folder.id)
        session.captureBoardIfNeeded()

        // Cartão de dentro da pasta não entra na seleção do mural.
        session.toggleSelection(inside.id)
        #expect(session.currentSelection.isEmpty)
        #expect(!session.isSelecting)

        session.toggleSelection(note.id)
        session.toggleSelection(folder.id)
        session.toggleSelection(kept.id)
        session.toggleSelection(kept.id)
        #expect(session.currentSelection == [note.id, folder.id])
        #expect(session.isSelecting)

        session.deleteSelection()
        #expect(model.item(id: note.id) == nil)
        #expect(model.item(id: folder.id) == nil)
        #expect(model.item(id: inside.id) == nil)
        #expect(model.item(id: kept.id) != nil)
        #expect(!session.isSelecting)
        await session.flushAndPrepareToLeave()

        let reloaded = BoardWindowSession(
            route: route, registry: BoardSessionRegistry(library: BoardLibrary(rootDirectory: directory)))
        try await makeReady(reloaded)
        #expect(reloaded.model?.rootItems.map(\.id) == [kept.id])
    }

    @Test("Trocar de nível limpa a seleção; dentro da pasta só os cartões dela entram")
    func selectionFollowsLevel() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Níveis")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        try await makeReady(session)
        let model = try #require(session.model)
        let note = model.createNote()
        let folder = model.createFolder(named: "Caixa")
        let inside = model.createNote(into: folder.id)
        session.captureBoardIfNeeded()

        session.toggleSelection(note.id)
        session.setNavigation(path: [.collection(folder.id)], filter: nil)
        #expect(session.currentSelection.isEmpty)
        session.toggleSelection(note.id)
        session.toggleSelection(inside.id)
        #expect(session.currentSelection == [inside.id])
        session.clearSelection()
        #expect(!session.isSelecting)
    }

    @Test("Aviso de apagar vários conta o que as pastas marcadas levam junto")
    func selectionDeleteWarning() {
        let note = BoardItem(kind: .text, title: "Nota")
        let full = BoardItem(kind: .folder, title: "Cheia")
        let empty = BoardItem(kind: .folder, title: "Vazia")
        let children = [full.id: 3, empty.id: 0]
        let count: (UUID) -> Int = { children[$0] ?? 0 }
        #expect(!ItemKind.deleteWarning(forSelection: [note], childCount: count).contains("pasta"))
        #expect(ItemKind.deleteWarning(forSelection: [note, empty], childCount: count).hasPrefix("Inclui 1 pasta sem nada dentro."))
        #expect(
            ItemKind.deleteWarning(forSelection: [full, empty], childCount: count)
                .hasPrefix("Inclui 2 pastas com 3 itens dentro"))
    }

    @Test("Sem o modelo ligado, nenhuma fila é criada e a nota dobra pela primeira frase")
    func sessionWithoutModel() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Sem modelo")
        let session = BoardWindowSession(
            route: route, registry: BoardSessionRegistry(library: library), usesOnDeviceModel: false)
        try await makeReady(session)
        #expect(session.keySentences == nil)
        let note = try #require(session.model?.importText("Primeira frase. Segunda frase.", as: .text))
        session.prioritizeKeySentences(for: note.id)
        let saved = try #require(session.model?.item(id: note.id))
        let result = try #require(NoteFolding.fold(for: saved))
        #expect(result.document.stretchIDs.count == 1)
        #expect(NoteFolding.notice(for: result) == nil)
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
            generation: session.presentationGeneration)
        session.delete(item.id)
        #expect(session.path.isEmpty)
        #expect(session.readingPosition(for: item.id) == nil)
    }
}
