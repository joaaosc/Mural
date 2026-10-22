import AppKit
import CoreGraphics
import Foundation
import MuralKit
import Testing

@testable import Mural

/// O ⌘V de links passando pela sessão da janela, como o mural faz: leitura, cartão e gravação.
@Suite("Colar links pela sessão da janela")
@MainActor
struct PasteLinkSessionTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralPasteLinks-\(UUID().uuidString)", isDirectory: true)
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

    @Test("Links lidos viram cartões na pasta pedida e continuam no mural reaberto")
    func pastedLinksAreCommittedAndSaved() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Links")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        await makeReady(session)
        let model = try #require(session.model)
        let folder = model.createFolder(named: "Pasta")

        let drafts = [
            LinkDraft(url: try #require(URL(string: "https://example.com/a")), title: "Página A"),
            LinkDraft(url: try #require(URL(string: "https://example.com/b"))),
        ]
        await session.importPasted(.links(drafts), into: folder.id, animation: nil)

        let links = model.board.items.filter { $0.kind == .link }
        #expect(links.map(\.title) == ["Página A", "example.com"])
        #expect(links.allSatisfy { $0.parentID == folder.id })
        #expect(model.lastError == nil)

        await session.flushAndPrepareToLeave()
        let saved = try #require(try await library.open(route)).board.items.filter { $0.kind == .link }
        #expect(saved.map(\.link?.url.absoluteString) == ["https://example.com/a", "https://example.com/b"])
    }

    @Test("Lista sem endereço da web avisa em lastError e não cria cartão")
    func emptyLinksReportAnError() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let session = BoardWindowSession(
            route: try await library.createNamedBoard("Vazio"), registry: BoardSessionRegistry(library: library))
        await makeReady(session)
        let model = try #require(session.model)
        let before = model.board.items.count

        await session.importPasted(.links([]), into: nil, animation: nil)

        #expect(model.board.items.count == before)
        #expect(model.lastError == "O conteúdo copiado não pôde virar um cartão.")
    }
}
