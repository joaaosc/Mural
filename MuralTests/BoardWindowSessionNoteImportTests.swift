import AppKit
import CoreGraphics
import Foundation
import MuralKit
import Testing

@testable import Mural

/// A nota do editor de texto virando um cartão de texto numa sessão de mural: imagens gravadas antes do cartão, fechamento e troca
/// de aba no meio, imagem perdida e mural só para ver.
@Suite("Importar a nota do editor numa sessão", .serialized)
@MainActor
struct BoardWindowSessionNoteImportTests {
    private func png() -> Data {
        let image = NSImage(size: NSSize(width: 16, height: 8), flipped: false) { rect in
            NSColor.green.setFill()
            rect.fill()
            return true
        }
        return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    }

    private func makeSession(_ directory: URL) async throws -> BoardWindowSession {
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Notas")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        await session.load()
        let metrics = CanvasScrollMetrics(
            contentOffset: .zero, containerSize: CGSize(width: 900, height: 700), contentSize: CGSize(width: 3_400, height: 2_800))
        for _ in 0..<3 where session.restorationPhase != .ready {
            session.restoreCanvas(boardID: session.boardID, generation: session.presentationGeneration, metrics: metrics)
        }
        try #require(session.restorationPhase == .ready)
        return session
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MuralNoteImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func noteWithImage(_ token: UUID) -> PastedNote {
        let id = UUID()
        let card = EmbeddedCard.contact(ContactSnapshot(givenName: "Ana"))
        let text = "Começo.\n\n\(NoteImageMarkup.cardLine(id: id, title: "Ana"))\n\n\(NoteImageMarkup.pendingLine(token: token))"
        return PastedNote(text: text, embeds: [id: card], images: [token: .data(png(), fileExtension: "png")])
    }

    private func pngFiles(under directory: URL) -> [String] {
        ((try? FileManager.default.subpathsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasSuffix(".png") }
    }

    @Test("A imagem é gravada antes de o cartão existir, e o texto gravado nunca tem a linha provisória")
    func imagesAreStoredBeforeTheCard() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try await makeSession(directory)
        let model = try #require(session.model)
        var textCardsWhenStoring = -1
        session.storeNoteImage = { source, model in
            textCardsWhenStoring = model.board.items.filter { $0.kind == .text }.count
            return await NoteImagePaste.store(source, with: model)
        }
        let token = UUID()

        let id = try #require(await session.importNote(noteWithImage(token)))

        #expect(textCardsWhenStoring == 0)
        let item = try #require(model.item(id: id))
        let text = try #require(item.text)
        #expect(!text.contains("mural-colando"))
        let names = NoteImageMarkup.referencedFileNames(in: text)
        #expect(names.count == 1 && item.attachments?.contains { $0.fileName == names[0] } == true)
        #expect(item.attachments?.contains { $0.isCard } == true)
    }

    @Test("Janela fechada no meio: nenhum cartão e nenhum arquivo sobra")
    func closedMidway() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try await makeSession(directory)
        let model = try #require(session.model)
        let gate = Gate()
        session.storeNoteImage = { source, model in
            await gate.pass()
            return await NoteImagePaste.store(source, with: model)
        }
        let task = Task { await session.importNote(noteWithImage(UUID())) }
        await gate.untilSomeoneWaits()
        await session.handleWindowWillClose()
        gate.open()

        #expect(await task.value == nil)
        #expect(model.board.items.allSatisfy { $0.kind != .text })
        #expect(pngFiles(under: directory).isEmpty, "\(pngFiles(under: directory))")
    }

    @Test("Troca de aba no meio não interrompe: o cartão entra com a imagem")
    func tabSwitchMidway() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try await makeSession(directory)
        let model = try #require(session.model)
        let gate = Gate()
        session.storeNoteImage = { source, model in
            await gate.pass()
            return await NoteImagePaste.store(source, with: model)
        }
        let task = Task { await session.importNote(noteWithImage(UUID())) }
        await gate.untilSomeoneWaits()
        session.suspendPresentation()
        gate.open()

        let id = try #require(await task.value)
        let item = try #require(model.item(id: id))
        #expect(NoteImageMarkup.referencedFileNames(in: item.text ?? "").count == 1)
        #expect(pngFiles(under: directory).count == 1)
    }

    @Test("Imagem que não pôde ser gravada: a linha sai, nenhum arquivo e o aviso fica no modelo")
    func failedImage() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try await makeSession(directory)
        let model = try #require(session.model)
        session.storeNoteImage = { _, _ in nil }

        let id = try #require(await session.importNote(noteWithImage(UUID())))

        let item = try #require(model.item(id: id))
        #expect(!(item.text ?? "").contains("mural-colando") && NoteImageMarkup.referencedFileNames(in: item.text ?? "").isEmpty)
        #expect(model.lastError == "Uma imagem não pôde ser colada.")
        #expect(pngFiles(under: directory).isEmpty)
    }

    @Test("Mural só para ver não recebe a nota")
    func readOnlyBoard() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try await makeSession(directory)
        let model = try #require(session.model)
        model.isReadOnly = true

        #expect(await session.importNote(noteWithImage(UUID())) == nil)
        #expect(model.board.items.isEmpty)
        #expect(pngFiles(under: directory).isEmpty)
    }
}

/// Trava de teste: quem chama `pass()` espera até `open()`; `untilSomeoneWaits()` volta quando alguém está esperando.
@MainActor
private final class Gate {
    private var waiting: CheckedContinuation<Void, Never>?
    private var watcher: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func pass() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiting = continuation
            watcher?.resume()
            watcher = nil
        }
    }

    func untilSomeoneWaits() async {
        guard waiting == nil else { return }
        await withCheckedContinuation { watcher = $0 }
    }

    func open() {
        isOpen = true
        waiting?.resume()
        waiting = nil
    }
}
