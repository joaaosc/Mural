import AppKit
import Foundation
import MuralKit
import Testing

@testable import Mural

@Suite("Imagens coladas em notas")
@MainActor
struct NoteImagePasteTests {
    // MARK: Apoio

    private func makeBitmap() -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 6, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 8, height: 6).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private func pngData() -> Data { makeBitmap().representation(using: .png, properties: [:])! }
    private func tiffData() -> Data { makeBitmap().tiffRepresentation! }
    private func jpegData() -> Data { makeBitmap().representation(using: .jpeg, properties: [:])! }

    private func withPasteboard(_ body: (NSPasteboard) throws -> Void) rethrows {
        let pasteboard = NSPasteboard(name: .init("mural-teste-\(UUID().uuidString)"))
        pasteboard.clearContents()
        defer {
            pasteboard.clearContents()
            pasteboard.releaseGlobally()
        }
        try body(pasteboard)
    }

    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralNoteImage-\(UUID().uuidString)", isDirectory: true)
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
        // O alvo é o último pedido de rolagem da sessão (sem pedido, a origem).
        let target = session.zoom.scrollRequest?.point ?? .zero
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

    private func fileExists(_ name: String, model: BoardModel) -> Bool {
        let item = BoardItem(kind: .image, title: "", fileName: name)
        return model.fileURL(for: item).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    // MARK: Leitura

    @Test("PNG vira dados png")
    func png() {
        withPasteboard { board in
            let data = pngData()
            board.setData(data, forType: .png)
            let pieces = NoteImagePaste.read(from: board)
            guard case .image(.data(let read, let ext))? = pieces?.first, pieces?.count == 1 else {
                Issue.record("esperava .data png")
                return
            }
            #expect(read == data)
            #expect(ext == "png")
        }
    }

    @Test("TIFF pede conversão")
    func tiff() {
        withPasteboard { board in
            board.setData(tiffData(), forType: .tiff)
            guard case .image(.needsPNGConversion)? = NoteImagePaste.read(from: board)?.first else {
                Issue.record("esperava conversão")
                return
            }
        }
    }

    @Test("JPEG vira dados jpg")
    func jpeg() {
        withPasteboard { board in
            board.setData(jpegData(), forType: NSPasteboard.PasteboardType("public.jpeg"))
            guard case .image(.data(_, let ext))? = NoteImagePaste.read(from: board)?.first else {
                Issue.record("esperava .data jpg")
                return
            }
            #expect(ext == "jpg")
        }
    }

    @Test("URL de arquivo PNG vira .file")
    func fileURL() throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("foto.png")
        try pngData().write(to: url)
        withPasteboard { board in
            board.writeObjects([url as NSURL])
            guard case .image(.file(let read))? = NoteImagePaste.read(from: board)?.first else {
                Issue.record("esperava .file")
                return
            }
            #expect(read.lastPathComponent == "foto.png")
        }
    }

    @Test("Arquivo de texto com ícone TIFF não é imagem")
    func textFileWithIcon() throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("nota.txt")
        try Data("oi".utf8).write(to: url)
        withPasteboard { board in
            board.writeObjects([url as NSURL])
            board.setData(tiffData(), forType: .tiff)
            #expect(NoteImagePaste.read(from: board) == nil)
        }
    }

    @Test("RTFD com texto, imagem e texto mantém a ordem")
    func rtfdOrder() throws {
        let text = NSMutableAttributedString(string: "antes\n")
        let wrapper = FileWrapper(regularFileWithContents: pngData())
        wrapper.preferredFilename = "figura.png"
        text.append(NSAttributedString(attachment: NSTextAttachment(fileWrapper: wrapper)))
        text.append(NSAttributedString(string: "\ndepois"))
        let data = try #require(text.rtfd(from: NSRange(location: 0, length: text.length)))
        withPasteboard { board in
            board.setData(data, forType: .rtfd)
            guard let pieces = NoteImagePaste.read(from: board), pieces.count == 3,
                case .text(let first) = pieces[0], case .image(.data(_, let ext)) = pieces[1],
                case .text(let last) = pieces[2]
            else {
                Issue.record("esperava [.text, .image, .text]")
                return
            }
            #expect(first.contains("antes") && !first.contains("\u{FFFC}"))
            #expect(last.contains("depois"))
            #expect(ext == "png")
        }
    }

    @Test("RTF só com texto e TIFF junto é colar texto")
    func rtfWithTIFF() throws {
        let text = NSAttributedString(string: "só texto")
        let data = try #require(text.rtf(from: NSRange(location: 0, length: text.length)))
        withPasteboard { board in
            board.setData(data, forType: .rtf)
            board.setData(text.rtfd(from: NSRange(location: 0, length: text.length)), forType: .rtfd)
            board.setData(tiffData(), forType: .tiff)
            #expect(NoteImagePaste.read(from: board) == nil)
        }
    }

    @Test("Texto com PNG junto vira imagem")
    func textWithPNG() {
        withPasteboard { board in
            board.setString("https://exemplo.com/a.png", forType: .string)
            board.setData(pngData(), forType: .png)
            guard case .image(.data)? = NoteImagePaste.read(from: board)?.first else {
                Issue.record("esperava imagem")
                return
            }
        }
    }

    @Test("Só texto não é imagem")
    func onlyText() {
        withPasteboard { board in
            board.setString("olá", forType: .string)
            #expect(NoteImagePaste.read(from: board) == nil)
        }
    }

    // MARK: Sessão

    private func makeSession(directory: URL) async throws -> (BoardWindowSession, UUID) {
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Notas")
        let registry = BoardSessionRegistry(library: library)
        let session = BoardWindowSession(route: route, registry: registry)
        try await makeReady(session)
        let note = try #require(session.model?.createNote())
        return (session, note.id)
    }

    @Test("appendImages acrescenta a linha da imagem ao fim da nota")
    func appendImages() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (session, id) = try await makeSession(directory: directory)
        let model = try #require(session.model)
        model.updateNote(id, title: "T", text: "Começo")
        await session.appendImages([.image(.data(pngData(), fileExtension: "png"))], toNote: id)
        let item = try #require(model.item(id: id))
        let attachment = try #require(item.attachments?.first)
        #expect(item.attachments?.count == 1)
        #expect(item.title == "T")
        #expect(item.text?.hasPrefix("Começo\n\n") == true)
        #expect(item.text?.hasSuffix(NoteImageMarkup.line(fileName: attachment.fileName)) == true)
        #expect(fileExists(attachment.fileName, model: model))
    }

    @Test("A imagem colada na edição continua na nota depois de fechar e reabrir o mural")
    func pastedImageSurvivesReopening() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Notas")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        try await makeReady(session)
        let id = try #require(session.model?.createNote()).id
        let source = directory.appendingPathComponent("foto.png")
        try pngData().write(to: source)

        // O editor põe o marcador no rascunho, grava a imagem (arquivo do Finder) e troca o marcador pela linha final.
        let token = UUID()
        session.setNoteDraft(NoteDraft(title: "Com foto", text: "Texto\n\n\(NoteImageMarkup.pendingLine(token: token))"), for: id)
        let attachment = try #require(await session.prepareNoteImages([.file(source)], for: id).first ?? nil)
        let line = NoteImageMarkup.line(fileName: attachment.fileName)
        session.replacePendingImage(token, with: line, in: id)
        session.commitNoteDrafts()
        await session.handleWindowWillClose()

        let reopened = BoardWindowSession(
            route: route, registry: BoardSessionRegistry(library: BoardLibrary(rootDirectory: directory)))
        try await makeReady(reopened)
        let model = try #require(reopened.model)
        let item = try #require(model.item(id: id))
        #expect(item.text == "Texto\n\n\(line)")
        #expect(item.attachments?.map(\.fileName) == [attachment.fileName])
        #expect(fileExists(attachment.fileName, model: model), "o arquivo da imagem continua em Items/")
        await reopened.handleWindowWillClose()
    }

    @Test("replacePendingImage troca o marcador no texto gravado")
    func replacePending() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (session, id) = try await makeSession(directory: directory)
        let model = try #require(session.model)
        let token = UUID()
        model.updateNote(id, title: "T", text: "a\n\n\(NoteImageMarkup.pendingLine(token: token))\n\nb")
        let line = NoteImageMarkup.line(fileName: "\(UUID().uuidString).png")
        session.replacePendingImage(token, with: line, in: id)
        #expect(model.item(id: id)?.text == "a\n\n\(line)\n\nb")
    }

    @Test("Apresentação invalidada no meio descarta a imagem")
    func invalidatedMidway() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (session, id) = try await makeSession(directory: directory)
        let model = try #require(session.model)
        // A gravação fica presa na trava até a apresentação mudar: a ordem não depende do tempo.
        let gate = Gate()
        session.storeNoteImage = { source, model in
            await gate.pass()
            return await NoteImagePaste.store(source, with: model)
        }
        let task = Task { await session.prepareNoteImages([.data(pngData(), fileExtension: "png")], for: id) }
        await gate.untilSomeoneWaits()
        session.invalidatePresentation()
        gate.open()
        let result = await task.value
        #expect(result.count == 1 && result[0] == nil)
        #expect(model.item(id: id)?.attachments?.isEmpty ?? true)
        let items = directory.appendingPathComponent("Items")
        let leftovers =
            (try? FileManager.default.subpathsOfDirectory(atPath: directory.path))?
            .filter { $0.hasSuffix(".png") } ?? []
        #expect(leftovers.isEmpty, "\(items.path): \(leftovers)")
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
