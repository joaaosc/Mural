import AppKit
import Foundation
import MuralKit
import Synchronization
import Testing

@testable import Mural

/// Um editor de mentira: um `NSFilePresenter` que, ao ser pedida a leitura coordenada, grava o texto "não salvo" no arquivo.
/// Com `delay`, só termina depois dele.
nonisolated final class FakeEditorPresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    private let newText: String
    private let delay: TimeInterval
    private let finished = Mutex(false)

    init(file: URL, newText: String, delay: TimeInterval = 0) {
        presentedItemURL = file
        self.newText = newText
        self.delay = delay
        super.init()
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
    }

    var hasFinished: Bool { finished.withLock { $0 } }

    func savePresentedItemChanges(completionHandler: @escaping @Sendable (Error?) -> Void) {
        let save: @Sendable () -> Void = { [self] in
            if let url = presentedItemURL { try? Data(newText.utf8).write(to: url) }
            finished.withLock { $0 = true }
            completionHandler(nil)
        }
        if delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: save)
        } else {
            save()
        }
    }

    /// Espera o editor terminar de gravar, para a limpeza não apagar a pasta no meio.
    func waitUntilFinished() async {
        for _ in 0..<100 where !hasFinished { try? await Task.sleep(for: .milliseconds(50)) }
    }
}

@Suite("Arquivos das cópias de edição")
struct PasteEditFilesTests {
    // MARK: Apoio

    private func makeRoots() throws -> (roots: PasteEditFiles.Roots, base: URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PasteEditFilesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let roots = PasteEditFiles.Roots(
            inside: base.appendingPathComponent("inside", isDirectory: true),
            visible: base.appendingPathComponent("visible", isDirectory: true))
        return (roots, base)
    }

    private func makeBitmap() -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 6, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(deviceRed: 0.9, green: 0.2, blue: 0.2, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 8, height: 6).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private func pngData() -> Data { makeBitmap().representation(using: .png, properties: [:])! }
    private func tiffData() -> Data { makeBitmap().tiffRepresentation! }
    private func jpegData() -> Data { makeBitmap().representation(using: .jpeg, properties: [:])! }

    private func pdfData() -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 100, height: 100)
        let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 10, y: 10, width: 50, height: 50))
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private func entries(of directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    private func writeText(_ text: String, roots: PasteEditFiles.Roots, board: String = "Casa") async throws -> PasteEditFiles.Session {
        try await PasteEditFiles.write(.text(text), as: .text, boardName: board, roots: roots)
    }

    // MARK: Nomes

    @Test("O nome da pasta tem a data em UTC e o id, e a data volta do nome")
    func folderNameRoundTrip() throws {
        let id = try #require(UUID(uuidString: "8C0B3C0E-4F59-4D2B-9B0E-5C1F0F3A7A11"))
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let name = PasteEditFiles.folderName(id: id, createdAt: date)

        #expect(name == "20231114-221320-8C0B3C0E-4F59-4D2B-9B0E-5C1F0F3A7A11")
        #expect(PasteEditFiles.creationDate(ofFolderNamed: name) == date)
    }

    @Test(
        "Nomes que não são de uma pasta de edição não têm data",
        arguments: [
            "", "Fotos", ".DS_Store", "20231114-221320", "20231114-221320-", "20231114-221320-não-é-uuid",
            "2023111-4221320-8C0B3C0E-4F59-4D2B-9B0E-5C1F0F3A7A11", "20231114_221320-8C0B3C0E-4F59-4D2B-9B0E-5C1F0F3A7A11",
            "99999999-999999-8C0B3C0E-4F59-4D2B-9B0E-5C1F0F3A7A11",
        ])
    func junkFolderNamesAreRejected(name: String) {
        #expect(PasteEditFiles.creationDate(ofFolderNamed: name) == nil)
    }

    @Test("O nome do arquivo troca barra e dois-pontos, junta espaços, corta em 80 e cai em 'Colar no mural' sem nome")
    func fileNames() {
        #expect(PasteEditFiles.fileName(boardName: "Casa", kind: .text) == "Colar em Casa.txt")
        #expect(PasteEditFiles.fileName(boardName: "Casa", kind: .image) == "Colar em Casa.png")
        #expect(PasteEditFiles.fileName(boardName: "Casa", kind: .pdf) == "Colar em Casa.pdf")
        #expect(PasteEditFiles.fileName(boardName: "Obra: 2/3", kind: .text) == "Colar em Obra- 2-3.txt")
        #expect(PasteEditFiles.fileName(boardName: "  Minha \n\t  casa  ", kind: .text) == "Colar em Minha casa.txt")
        #expect(
            PasteEditFiles.fileName(boardName: String(repeating: "a", count: 200), kind: .pdf) == "Colar em "
                + String(repeating: "a", count: 80) + ".pdf")
        for blank in ["", "   ", "\n\t "] {
            #expect(PasteEditFiles.fileName(boardName: blank, kind: .image) == "Colar no mural.png")
        }
    }

    @Test("Texto vai para a raiz de dentro; imagem e PDF, para a visível")
    func rootsPerKind() {
        let roots = PasteEditFiles.Roots(inside: URL(filePath: "/a"), visible: URL(filePath: "/b"))

        #expect(roots.root(for: .text) == URL(filePath: "/a"))
        #expect(roots.root(for: .image) == URL(filePath: "/b"))
        #expect(roots.root(for: .pdf) == URL(filePath: "/b"))
    }

    // MARK: Gravar e ler

    @Test("Texto: grava em UTF-8 na raiz de dentro, com o atributo de codificação, e lê de volta")
    func textRoundTrip() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }

        let session = try await writeText("Olá, mundo ✓", roots: roots)

        #expect(session.kind == .text)
        #expect(session.file.path.hasPrefix(roots.inside.path + "/"))
        #expect(session.file.lastPathComponent == "Colar em Casa.txt")
        #expect(session.folder.lastPathComponent == PasteEditFiles.folderName(id: session.id, createdAt: session.createdAt))
        #expect(try Data(contentsOf: session.file) == Data("Olá, mundo ✓".utf8))
        var buffer = [UInt8](repeating: 0, count: 64)
        let length = getxattr(session.file.path, "com.apple.TextEncoding", &buffer, buffer.count, 0, 0)
        #expect(length > 0)
        #expect(String(decoding: buffer.prefix(max(length, 0)), as: UTF8.self) == "utf-8;134217984")
        guard case .text(let text) = try await PasteEditFiles.read(session) else {
            Issue.record("deveria ler texto")
            return
        }
        #expect(text == "Olá, mundo ✓")
    }

    @Test("TIFF vira PNG na raiz visível")
    func tiffBecomesPNG() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }

        let session = try await PasteEditFiles.write(
            .imageNeedingConversion(tiffData()), as: .image, boardName: "Casa", roots: roots)

        #expect(session.file.path.hasPrefix(roots.visible.path + "/"))
        #expect(session.file.lastPathComponent == "Colar em Casa.png")
        #expect(try Data(contentsOf: session.file).starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }

    @Test("Imagem em PNG grava como veio e lê como imagem colada")
    func pngRoundTrip() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }
        let png = pngData()

        let session = try await PasteEditFiles.write(
            .data(png, fileExtension: "png", kind: .image, title: "x"), as: .image, boardName: "Casa", roots: roots)

        #expect(try Data(contentsOf: session.file) == png)
        guard case .data(let data, let fileExtension, let kind, let title) = try await PasteEditFiles.read(session) else {
            Issue.record("deveria ler .data")
            return
        }
        #expect(data == png)
        #expect(fileExtension == "png")
        #expect(kind == .image)
        #expect(title == "Imagem colada")
    }

    @Test("Imagem que o editor devolveu em outro formato pede conversão")
    func jpegNeedsConversion() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }
        let session = try await PasteEditFiles.write(
            .data(pngData(), fileExtension: "png", kind: .image, title: "x"), as: .image, boardName: "Casa", roots: roots)
        let jpeg = jpegData()
        try jpeg.write(to: session.file)

        guard case .imageNeedingConversion(let data) = try await PasteEditFiles.read(session) else {
            Issue.record("deveria pedir conversão")
            return
        }
        #expect(data == jpeg)
    }

    @Test("PDF: ida e volta, e um arquivo que não é PDF não pode ser lido")
    func pdfRoundTrip() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }
        let pdf = pdfData()
        let session = try await PasteEditFiles.write(
            .data(pdf, fileExtension: "pdf", kind: .pdf, title: "x"), as: .pdf, boardName: "Casa", roots: roots)

        guard case .data(let data, let fileExtension, let kind, let title) = try await PasteEditFiles.read(session) else {
            Issue.record("deveria ler .data")
            return
        }
        #expect(data == pdf)
        #expect(fileExtension == "pdf")
        #expect(kind == .pdf)
        #expect(title == "PDF colado")

        try Data("isto não é um PDF".utf8).write(to: session.file)
        await #expect(throws: PasteEditFiles.Failure.unreadable) { try await PasteEditFiles.read(session) }
    }

    @Test("Texto em branco na edição é edição vazia")
    func blankTextIsEmpty() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }
        let session = try await writeText("Algo", roots: roots)
        try Data("  \n\t".utf8).write(to: session.file)

        await #expect(throws: PasteEditFiles.Failure.empty) { try await PasteEditFiles.read(session) }
    }

    @Test("Se o editor renomeou o arquivo, vale o único arquivo que sobrou na pasta")
    func renamedFileIsFound() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }
        let session = try await writeText("Original", roots: roots)
        let renamed = session.folder.appendingPathComponent("Outro nome.txt")
        try FileManager.default.moveItem(at: session.file, to: renamed)

        guard case .text(let text) = try await PasteEditFiles.read(session) else {
            Issue.record("deveria ler texto")
            return
        }
        #expect(text == "Original")
    }

    @Test("Sem o arquivo e sem um único substituto, a cópia não foi encontrada")
    func missingFile() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }
        let session = try await writeText("Original", roots: roots)

        try FileManager.default.removeItem(at: session.file)
        await #expect(throws: PasteEditFiles.Failure.missing) { try await PasteEditFiles.read(session) }

        try Data("a".utf8).write(to: session.folder.appendingPathComponent("a.txt"))
        try Data("b".utf8).write(to: session.folder.appendingPathComponent("b.txt"))
        await #expect(throws: PasteEditFiles.Failure.missing) { try await PasteEditFiles.read(session) }
    }

    @Test("Conteúdo que não combina com o tipo não é editável e não deixa pasta")
    func unsupportedContent() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }

        await #expect(throws: PasteEditFiles.Failure.unsupported) {
            try await PasteEditFiles.write(.links([]), as: .text, boardName: "Casa", roots: roots)
        }
        await #expect(throws: PasteEditFiles.Failure.unsupported) {
            try await PasteEditFiles.write(.text("oi"), as: .image, boardName: "Casa", roots: roots)
        }
        await #expect(throws: PasteEditFiles.Failure.unsupported) {
            try await PasteEditFiles.write(.nothing, as: .pdf, boardName: "Casa", roots: roots)
        }
        #expect(entries(of: roots.inside).isEmpty)
        #expect(entries(of: roots.visible).isEmpty)
    }

    @Test("Imagem que não converte para PNG não pode ser lida e não deixa pasta")
    func unconvertibleImage() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }

        await #expect(throws: PasteEditFiles.Failure.unreadable) {
            try await PasteEditFiles.write(
                .imageNeedingConversion(Data("não é imagem".utf8)), as: .image, boardName: "Casa", roots: roots)
        }
        #expect(entries(of: roots.visible).isEmpty)
    }

    // MARK: Leitura coordenada

    @Test("A leitura coordenada traz o que o editor ainda não tinha salvo")
    func readReturnsUnsavedChanges() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }
        let session = try await writeText("Olá", roots: roots)
        let presenter = FakeEditorPresenter(file: session.file, newText: "Olá mundo")
        NSFileCoordinator.addFilePresenter(presenter)
        defer { NSFileCoordinator.removeFilePresenter(presenter) }

        guard case .text(let text) = try await PasteEditFiles.read(session) else {
            Issue.record("deveria ler texto")
            return
        }

        #expect(text == "Olá mundo")
        #expect(presenter.hasFinished)
    }

    @Test("Um editor lento passa do prazo: lê a última versão salva")
    func slowEditorFallsBackToTheSavedVersion() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }
        let session = try await writeText("Olá", roots: roots)
        let presenter = FakeEditorPresenter(file: session.file, newText: "Olá mundo", delay: 1)
        NSFileCoordinator.addFilePresenter(presenter)
        defer { NSFileCoordinator.removeFilePresenter(presenter) }

        let started = ContinuousClock.now
        let content = try await PasteEditFiles.read(session, timeout: .milliseconds(200))
        let elapsed = ContinuousClock.now - started
        await presenter.waitUntilFinished()

        guard case .text(let text) = content else {
            Issue.record("deveria ler texto")
            return
        }
        #expect(text == "Olá")
        #expect(elapsed < .milliseconds(900))
    }

    // MARK: Apagar

    @Test("Apagar remove a pasta e a raiz vazia, mas mantém a raiz que tem outra edição")
    func removeKeepsRootsWithOtherSessions() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }
        let first = try await PasteEditFiles.write(
            .data(pngData(), fileExtension: "png", kind: .image, title: "x"), as: .image, boardName: "Casa", roots: roots,
            id: UUID(), now: Date(timeIntervalSince1970: 1_700_000_000))
        let second = try await PasteEditFiles.write(
            .data(pngData(), fileExtension: "png", kind: .image, title: "x"), as: .image, boardName: "Casa", roots: roots,
            id: UUID(), now: Date(timeIntervalSince1970: 1_700_000_100))

        await PasteEditFiles.remove(first)
        #expect(!exists(first.folder))
        #expect(exists(second.folder))
        #expect(exists(roots.visible))

        await PasteEditFiles.remove(second)
        #expect(!exists(second.folder))
        #expect(!exists(roots.visible))
    }

    @Test("Apagar uma edição que já sumiu não falha")
    func removeIsBestEffort() async throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }
        let session = try await writeText("Olá", roots: roots)

        await PasteEditFiles.remove(session)
        await PasteEditFiles.remove(session)

        #expect(!exists(session.folder))
    }

    // MARK: Limpeza

    @Test("A limpeza apaga só as pastas velhas pelo nome, poupa as ativas e as de outro nome e ignora as datas dos arquivos")
    func sweepUsesFolderNames() throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func make(_ name: String, in root: URL) throws -> URL {
            let url = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        func named(_ age: TimeInterval) -> String {
            PasteEditFiles.folderName(id: UUID(), createdAt: now.addingTimeInterval(-age))
        }
        let old = try make(named(2 * 86_400), in: roots.inside)
        let oldVisible = try make(named(3 * 86_400), in: roots.visible)
        let young = try make(named(3_600), in: roots.inside)
        let active = try make(named(5 * 86_400), in: roots.visible)
        let foreign = try make("Fotos", in: roots.inside)
        // A data do arquivo não conta: a pasta nova com data antiga fica; a velha com data de agora é apagada.
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: young.path)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: old.path)

        let removed = PasteEditFiles.sweep(roots: roots, keeping: [active], now: now)

        #expect(Set(removed.map(\.lastPathComponent)) == [old.lastPathComponent, oldVisible.lastPathComponent])
        #expect(!exists(old))
        #expect(!exists(oldVisible))
        #expect(exists(young))
        #expect(exists(active))
        #expect(exists(foreign))
        #expect(exists(roots.visible), "a raiz visível tem uma edição ativa")
    }

    @Test("A limpeza remove a raiz visível quando fica vazia")
    func sweepRemovesAnEmptyVisibleRoot() throws {
        let (roots, base) = try makeRoots()
        defer { try? FileManager.default.removeItem(at: base) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let old = roots.visible.appendingPathComponent(
            PasteEditFiles.folderName(id: UUID(), createdAt: now.addingTimeInterval(-2 * PasteEditFiles.maxAge)), isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)

        let removed = PasteEditFiles.sweep(roots: roots, now: now)

        #expect(removed.count == 1)
        #expect(!exists(roots.visible))
    }
}
