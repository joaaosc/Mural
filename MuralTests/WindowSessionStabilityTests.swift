import CoreGraphics
import Foundation
import MuralKit
import Testing

@testable import Mural

/// Regressões de estabilidade do adaptador da janela: tokens que sobrevivem ao
/// autosave, restauração que nunca prende o canvas, janela fechada que não grava e
/// gravação do canvas fora do caminho de cada quadro.
@Suite("Estabilidade da sessão da janela")
@MainActor
struct WindowSessionStabilityTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralStability-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private let viewport = CGSize(width: 900, height: 700)
    private let contentSize = CGSize(width: 3_400, height: 2_800)

    private func metrics(offset: CGPoint, viewport: CGSize? = nil) -> CanvasScrollMetrics {
        CanvasScrollMetrics(contentOffset: offset, containerSize: viewport ?? self.viewport, contentSize: contentSize)
    }

    private func drive(_ session: BoardWindowSession, _ metrics: CanvasScrollMetrics) {
        session.restoreCanvas(boardID: session.boardID, generation: session.presentationGeneration, metrics: metrics)
    }

    private func makeReady(_ session: BoardWindowSession) async {
        await session.load()
        for _ in 0..<3 where session.restorationPhase != .ready {
            drive(session, metrics(offset: .zero))
        }
        #expect(session.restorationPhase == .ready)
    }

    @Test("O token de leitura continua válido depois de um autosave")
    func readingTokenSurvivesAutosave() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let session = BoardWindowSession(
            route: try await library.createNamedBoard("Leitura"), registry: BoardSessionRegistry(library: library))
        await makeReady(session)
        let item = try #require(session.model?.importText("texto longo"))
        let token = session.readingPresentationToken(for: item.id)
        let savedGeneration = session.generation

        session.captureBoardIfNeeded()
        await session.flushAndPrepareToLeave()
        #expect(session.generation != savedGeneration, "o autosave deveria avançar a geração do domínio")

        #expect(session.acceptsReadingPresentation(token))
        session.recordReadingPosition(.item(itemID: item.id, visibleContentY: 480), token: token)
        #expect(session.readingPosition(for: item.id) == .item(itemID: item.id, visibleContentY: 480))
    }

    @Test("A restauração do canvas termina mesmo com um autosave no meio")
    func canvasRestorationCompletesAcrossAutosave() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let session = BoardWindowSession(
            route: try await library.createNamedBoard("Canvas"), registry: BoardSessionRegistry(library: library))
        await session.load()
        #expect(session.restorationPhase == .awaitingLayout)

        // Colar durante a restauração grava conteúdo e avança a geração do domínio.
        _ = session.model?.importText("colado durante a restauração")
        session.captureBoardIfNeeded()
        await session.flushAndPrepareToLeave()

        drive(session, metrics(offset: .zero))
        drive(session, metrics(offset: .zero))
        #expect(session.restorationPhase == .ready)
    }

    @Test("O watchdog libera o canvas quando a posição salva é inalcançável")
    func watchdogReleasesUnreachableRestoration() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let session = BoardWindowSession(
            route: try await library.createNamedBoard("Inalcançável"), registry: BoardSessionRegistry(library: library))
        session.restorationTimeout = .milliseconds(50)
        await session.load()
        // O ScrollView nunca chega ao alvo (origem): o offset fica preso longe dele.
        drive(session, metrics(offset: CGPoint(x: 500, y: 500)))
        #expect(session.restorationPhase == .applyingPosition)
        drive(session, metrics(offset: CGPoint(x: 500, y: 500)))
        try await Task.sleep(for: .milliseconds(300))
        #expect(session.restorationPhase == .ready)
    }

    @Test("Rolar com o canvas pronto não grava a cada quadro; resize grava uma vez")
    func readyCanvasRecordsOnlyOnResize() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let session = BoardWindowSession(
            route: try await library.createNamedBoard("Rolagem"), registry: BoardSessionRegistry(library: library))
        await makeReady(session)
        let before = session.workspace

        for step in 1...20 {
            drive(session, metrics(offset: CGPoint(x: Double(step) * 10, y: Double(step) * 7)))
        }
        #expect(session.workspace == before, "a rolagem não pode gravar o workspace a cada quadro")

        drive(session, metrics(offset: CGPoint(x: 200, y: 140), viewport: CGSize(width: 1_200, height: 800)))
        try await Task.sleep(for: .milliseconds(500))
        #expect(session.workspace.canvas != before.canvas, "o resize deveria gravar o centro visível")
    }

    @Test("Depois de fechada, a janela não grava mais nada")
    func closedWindowDoesNotWrite() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Fechada")
        let registry = BoardSessionRegistry(library: library)
        let session = BoardWindowSession(route: route, registry: registry)
        await makeReady(session)
        _ = session.model?.importText("antes de fechar")
        session.captureBoardIfNeeded()

        await session.handleWindowWillClose()
        #expect(session.isClosed)
        #expect(await registry.session(for: session.boardID) == nil)

        _ = session.model?.importText("depois de fechar")
        session.captureBoardIfNeeded()
        session.recordCanvas(CanvasWorkspaceState(confirmedZoom: 2))
        await session.flushAndPrepareToLeave()
        try await Task.sleep(for: .milliseconds(400))

        let titles = try #require(try await library.open(route)).board.items.map(\.title)
        #expect(titles.contains { $0.contains("antes de fechar") })
        #expect(!titles.contains { $0.contains("depois de fechar") })
    }

    @Test("Fechar uma janela enquanto outra reabre o mesmo mural não derruba a sessão")
    func fastReopenKeepsSharedSessionAlive() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Reabrir")
        let registry = BoardSessionRegistry(library: library)
        let closing = BoardWindowSession(route: route, registry: registry)
        let reopening = BoardWindowSession(route: route, registry: registry)
        await makeReady(closing)
        await makeReady(reopening)
        #expect(closing.domainSession === reopening.domainSession)

        await closing.handleWindowWillClose()
        #expect(await registry.session(for: reopening.boardID) === reopening.domainSession)

        _ = reopening.model?.importText("gravado pela janela nova")
        reopening.captureBoardIfNeeded()
        await reopening.flushAndPrepareToLeave()
        #expect(reopening.isDirty == false)
        #expect(try #require(try await library.open(route)).board.items.contains { $0.title.contains("janela nova") })
    }

    @Test("Renomear pela janela não volta ao nome antigo no autosave seguinte")
    func renameSurvivesLaterAutosave() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Antigo")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        await makeReady(session)

        await session.rename(to: "Novo nome")
        #expect(session.title == "Novo nome")
        _ = session.model?.importText("depois de renomear")
        session.captureBoardIfNeeded()
        await session.flushAndPrepareToLeave()

        #expect(try await library.open(route)?.manifest.name == "Novo nome")
    }
}
