import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import MuralKit

@Suite("Imagem colada em nota")
struct NoteImageMarkupTests {
    private let name = "5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01.png"
    private let other = "7C1D5E3F-9D1C-4C2A-8E86-4F2B8A3BAD02.jpg"

    @Test("A linha de imagem usa o texto alternativo padrão ou o dado")
    func line() {
        #expect(NoteImageMarkup.line(fileName: name) == "![Imagem colada](\(name))")
        #expect(NoteImageMarkup.line(fileName: name, alt: "Foto") == "![Foto](\(name))")
    }

    @Test("Inserção sem texto em volta é só a linha")
    func insertionAlone() {
        #expect(NoteImageMarkup.insertion(of: ["A"], after: "", before: "") == "A")
        #expect(NoteImageMarkup.insertion(of: [], after: "x", before: "y").isEmpty)
    }

    @Test("Inserção separa a imagem do texto anterior e do seguinte")
    func insertionBetweenText() {
        #expect(NoteImageMarkup.insertion(of: ["A"], after: "antes", before: "depois") == "\n\nA\n\n")
        #expect(NoteImageMarkup.insertion(of: ["A"], after: "antes\n", before: "\ndepois") == "\nA\n")
        #expect(NoteImageMarkup.insertion(of: ["A"], after: "antes\n\n", before: "\n\ndepois") == "A")
        #expect(NoteImageMarkup.insertion(of: ["A"], after: "antes", before: "") == "\n\nA")
        #expect(NoteImageMarkup.insertion(of: ["A"], after: "", before: "depois") == "A\n\n")
    }

    @Test("Várias imagens ficam em blocos separados por linha em branco")
    func insertionSeveral() {
        #expect(NoteImageMarkup.insertion(of: ["A", "B", "C"], after: "x", before: "y") == "\n\nA\n\nB\n\nC\n\n")
    }

    @Test("Nomes citados: só anexos, sem repetição, fora de cerca de código")
    func referenced() {
        let text = """
            Início
            ![a](\(name))
            ![b](\(other))
            ![c](\(name))
            ![d](https://exemplo.com/\(name))
            ![e](../\(other))
            ![f](foto.png)
            texto ![g](\(other)) no meio da frase
            ```
            ![h](5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C99.png)
            ```
            """
        #expect(NoteImageMarkup.referencedFileNames(in: text) == [name, other])
        #expect(NoteImageMarkup.referencedFileNames(in: "sem imagens").isEmpty)
    }

    @Test(
        "Nome de anexo aceito",
        arguments: [
            "5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01.png", "5b0f4c2e-8c0b-4b1f-9d75-3e1a7f2a9c01.JPEG",
            "5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01.heic", "5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01.webp",
        ])
    func acceptsName(_ value: String) {
        #expect(NoteImageMarkup.isAttachmentName(value))
    }

    @Test(
        "Nome de anexo recusado",
        arguments: [
            "", "foto.png", "5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01", "5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01.mov",
            "5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01.png.png", "../5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01.png",
            "a/5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01.png", "5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01..png",
            "https://x.com/5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01.png",
        ])
    func rejectsName(_ value: String) {
        #expect(!NoteImageMarkup.isAttachmentName(value))
    }

    @Test("O marcador provisório é trocado pela linha final")
    func replacingPending() {
        let token = UUID()
        let marker = NoteImageMarkup.pendingLine(token: token)
        #expect(marker == "![Colando imagem…](mural-colando:\(token.uuidString))")
        #expect(NoteImageMarkup.isPendingLine(marker))
        #expect(NoteImageMarkup.isPendingSource("mural-colando:\(token.uuidString)"))
        #expect(!NoteImageMarkup.isPendingSource(name))
        let text = "antes\n\n\(marker)\n\ndepois"
        #expect(NoteImageMarkup.replacingPending(token, with: "![x](\(name))", in: text) == "antes\n\n![x](\(name))\n\ndepois")
    }

    @Test("Marcador removido não deixa duas linhas em branco seguidas")
    func removingPending() {
        let token = UUID()
        let marker = NoteImageMarkup.pendingLine(token: token)
        #expect(NoteImageMarkup.replacingPending(token, with: "", in: "antes\n\n\(marker)\n\ndepois") == "antes\n\ndepois")
        #expect(NoteImageMarkup.replacingPending(token, with: "", in: "\(marker)\n\ndepois") == "depois")
        #expect(NoteImageMarkup.replacingPending(token, with: "", in: "antes\n\n\(marker)") == "antes")
        #expect(NoteImageMarkup.replacingPending(token, with: "", in: marker) == "")
        #expect(NoteImageMarkup.replacingPending(token, with: "", in: "a\n\(marker)\nb") == "a\nb")
    }

    @Test("Sem o marcador no texto, devolve nil")
    func missingPending() {
        #expect(NoteImageMarkup.replacingPending(UUID(), with: "x", in: "texto") == nil)
        let marker = NoteImageMarkup.pendingLine(token: UUID())
        #expect(NoteImageMarkup.replacingPending(UUID(), with: "x", in: marker) == nil)
    }

    @Test("O título pula linhas de imagem e o marcador")
    func titleSkipsImages() {
        let marker = NoteImageMarkup.pendingLine(token: UUID())
        #expect(ContentClassifier.title(forText: "![a](\(name))\n\n\(marker)\nLegenda") == "Legenda")
        #expect(ContentClassifier.title(forText: "![a](\(name))") == "Nota")
        #expect(ContentClassifier.title(forText: marker) == "Nota")
    }

    @Test("Versão do formato 5 só com anexo")
    func formatVersion() {
        let plain = BoardItem(kind: .text, title: "N", text: "x")
        #expect(Board(items: [plain]).requiredFormatVersion == 1)
        #expect(Board(items: [BoardItem(kind: .text, title: "N", attachments: [])]).requiredFormatVersion == 1)
        let attachment = NoteAttachment(fileName: name, pixelWidth: 1, pixelHeight: 1)
        let withImage = BoardItem(kind: .text, title: "N", attachments: [attachment])
        #expect(Board(items: [withImage]).requiredFormatVersion == 5)
        #expect(Board.currentFormatVersion >= 5)
    }

    @Test("Mural sem o campo de anexos continua abrindo")
    func decodesWithoutAttachments() throws {
        let item = BoardItem(kind: .text, title: "N")
        let data = try JSONEncoder().encode(item)
        #expect(!String(decoding: data, as: UTF8.self).contains("attachments"))
        #expect(try JSONDecoder().decode(BoardItem.self, from: data).attachments == nil)
    }

    @Test("Nomes de arquivo do cartão: obrigatórios e citados no texto")
    func assetFileNames() {
        let attachment = NoteAttachment(fileName: name, pixelWidth: 1, pixelHeight: 1)
        let note = BoardItem(kind: .text, title: "N", text: "![a](\(name))\n![b](\(other))", attachments: [attachment])
        #expect(note.requiredAssetFileNames == [name])
        #expect(note.assetFileNames == [name, other])
        let photo = BoardItem(kind: .image, title: "P", fileName: "x.png", text: "![a](\(other))")
        #expect(photo.assetFileNames == ["x.png"])

        let repeated = BoardItem(
            kind: .image,
            title: "Repetida",
            fileName: name,
            attachments: [
                NoteAttachment(fileName: name, pixelWidth: 1, pixelHeight: 1),
                NoteAttachment(fileName: other, pixelWidth: 1, pixelHeight: 1),
            ])
        #expect(repeated.requiredAssetFileNames == [name, other])
    }
}

@MainActor
@Suite("Imagem colada em nota: arquivos e modelo")
struct NoteImageStorageTests {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralNoteImage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func pngData(width: Int = 6, height: Int = 4) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func exists(_ model: BoardModel, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: model.importer.itemsDirectory.appendingPathComponent(name).path)
    }

    private func makeModel(
        _ directory: URL, persistence: BoardModel.Persistence = .immediate
    ) -> BoardModel {
        BoardModel(board: Board(), store: BoardStore(directory: directory), persistence: persistence)
    }

    /// Nota que cita o anexo (o texto tem a linha da imagem).
    private func makeNote(in model: BoardModel, attachment: NoteAttachment, text: String? = nil) -> BoardItem {
        let note = model.createNote()
        model.addNoteAttachment(attachment, to: note.id)
        model.updateNote(note.id, title: "Nota", text: text ?? NoteImageMarkup.line(fileName: attachment.fileName))
        return model.item(id: note.id)!
    }

    // MARK: Importador

    @Test("importNoteImage grava o PNG com o nome certo e lê o tamanho")
    func importsData() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let importer = ItemImporter(itemsDirectory: directory.appendingPathComponent("Items"))
        let attachment = try importer.importNoteImage(data: try pngData(width: 6, height: 4), fileExtension: "PNG")
        #expect(attachment.pixelWidth == 6 && attachment.pixelHeight == 4)
        #expect(NoteImageMarkup.isAttachmentName(attachment.fileName))
        #expect(attachment.fileName.hasSuffix(".png"))
        #expect(FileManager.default.fileExists(atPath: importer.itemsDirectory.appendingPathComponent(attachment.fileName).path))
    }

    @Test("Dados que não são imagem lançam e não deixam arquivo")
    func rejectsNonImage() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let importer = ItemImporter(itemsDirectory: directory)
        #expect(throws: ImportError.self) { try importer.importNoteImage(data: Data([1, 2, 3]), fileExtension: "png") }
        #expect(throws: ImportError.self) { try importer.importNoteImage(data: try pngData(), fileExtension: "mov") }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("importNoteImage(fileAt:) copia só arquivo de imagem")
    func importsFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("foto.PNG")
        try pngData(width: 3, height: 5).write(to: source)
        let text = directory.appendingPathComponent("a.txt")
        try Data("oi".utf8).write(to: text)
        let importer = ItemImporter(itemsDirectory: directory.appendingPathComponent("Items"))
        let attachment = try importer.importNoteImage(fileAt: source)
        #expect(attachment.pixelWidth == 3 && attachment.pixelHeight == 5)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(throws: ImportError.self) { try importer.importNoteImage(fileAt: text) }
    }

    @Test("removeFile(named:) ignora nomes inseguros")
    func removeNamedIsSafe() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let items = directory.appendingPathComponent("Items")
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        let outside = directory.appendingPathComponent("fora.txt")
        try Data("x".utf8).write(to: outside)
        let importer = ItemImporter(itemsDirectory: items)
        importer.removeFile(named: "../fora.txt")
        importer.removeFile(named: "")
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    // MARK: Modelo

    @Test("addNoteAttachment grava e cita o arquivo na hora")
    func addPersists() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeModel(directory)
        let note = model.createNote()
        let attachment = try #require(await model.prepareNoteImage(data: try pngData(), fileExtension: "png"))
        #expect(model.addNoteAttachment(attachment, to: note.id))
        #expect(model.addNoteAttachment(attachment, to: note.id))
        #expect(model.item(id: note.id)?.attachments == [attachment])
        let saved = try #require(try BoardStore(directory: directory).load())
        #expect(saved.item(id: note.id)?.attachments == [attachment])
        #expect(saved.formatVersion == 5)
        let sticky = model.createSticky()
        #expect(!model.addNoteAttachment(attachment, to: sticky.id))
    }

    @Test("discardNoteImage apaga o arquivo que nenhum cartão cita")
    func discardUncited() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeModel(directory)
        let free = try #require(await model.prepareNoteImage(data: try pngData(), fileExtension: "png"))
        let cited = try #require(await model.prepareNoteImage(data: try pngData(), fileExtension: "png"))
        model.addNoteAttachment(cited, to: model.createNote().id)
        model.discardNoteImage(free)
        model.discardNoteImage(cited)
        #expect(!exists(model, free.fileName))
        #expect(exists(model, cited.fileName))
    }

    @Test("updateNote sem a linha tira o anexo e apaga o arquivo depois de gravar")
    func updateDropsAttachment() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeModel(directory)
        let attachment = try #require(await model.prepareNoteImage(data: try pngData(), fileExtension: "png"))
        let note = makeNote(in: model, attachment: attachment, text: "Olá\n\n" + NoteImageMarkup.line(fileName: attachment.fileName))
        #expect(note.attachments == [attachment])
        model.updateNote(note.id, title: "Nota", text: "Olá")
        #expect(model.item(id: note.id)?.attachments == nil)
        #expect(!exists(model, attachment.fileName))
        let saved = try #require(try BoardStore(directory: directory).load())
        #expect(saved.item(id: note.id)?.attachments == nil)
        #expect(saved.formatVersion == 1)
    }

    @Test("Reconciliação preserva duplicatas legadas válidas e remove as demais")
    func reconcilePreservesLegacyAttachmentOrder() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeModel(directory)
        let first = try #require(await model.prepareNoteImage(data: try pngData(), fileExtension: "png"))
        let second = try #require(await model.prepareNoteImage(data: try pngData(), fileExtension: "png"))
        let note = makeNote(in: model, attachment: first)
        model.addNoteAttachment(second, to: note.id)
        model.updateNote(
            note.id,
            title: "Nota",
            text: "\(NoteImageMarkup.line(fileName: first.fileName))\n\n\(NoteImageMarkup.line(fileName: second.fileName))")

        var corrupted = model.board
        let index = try #require(corrupted.items.firstIndex(where: { $0.id == note.id }))
        corrupted.items[index].attachments = [first, first, second]
        model.board = corrupted

        model.updateNote(note.id, title: "Nota", text: NoteImageMarkup.line(fileName: first.fileName))
        #expect(model.item(id: note.id)?.attachments == [first, first])
        #expect(exists(model, first.fileName))
        #expect(!exists(model, second.fileName))
    }

    @Test("updateNote adota o nome citado cujo arquivo existe")
    func updateAdoptsCitedFile() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeModel(directory)
        let attachment = try #require(await model.prepareNoteImage(data: try pngData(width: 7, height: 2), fileExtension: "png"))
        let note = model.createNote()
        model.updateNote(note.id, title: "", text: NoteImageMarkup.line(fileName: attachment.fileName))
        #expect(model.item(id: note.id)?.attachments == [attachment])
        #expect(model.item(id: note.id)?.title == "Nota")
        // Nome citado sem arquivo não vira anexo.
        model.updateNote(note.id, title: "", text: "![x](\(UUID().uuidString).png)")
        #expect(model.item(id: note.id)?.attachments == nil)
    }

    @Test("Nome citado por outra nota não é apagado")
    func sharedNameSurvives() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeModel(directory)
        let attachment = try #require(await model.prepareNoteImage(data: try pngData(), fileExtension: "png"))
        let first = makeNote(in: model, attachment: attachment)
        let second = makeNote(in: model, attachment: attachment)
        model.updateNote(first.id, title: "Nota", text: "sem imagem")
        #expect(exists(model, attachment.fileName))
        model.delete(second.id)
        #expect(!exists(model, attachment.fileName))
    }

    @Test("Apagar a nota apaga o anexo, a não ser que outra nota o cite")
    func deleteNote() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeModel(directory)
        let attachment = try #require(await model.prepareNoteImage(data: try pngData(), fileExtension: "png"))
        let first = makeNote(in: model, attachment: attachment)
        let second = makeNote(in: model, attachment: attachment)
        model.delete(first.id)
        #expect(exists(model, attachment.fileName))
        model.delete(second.id)
        #expect(!exists(model, attachment.fileName))
    }

    @Test("No modo adiado, o arquivo só some quando a versão gravada não o cita")
    func deferredWaitsForPersisted() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeModel(directory, persistence: .deferred)
        let attachment = try #require(await model.prepareNoteImage(data: try pngData(), fileExtension: "png"))
        let note = makeNote(in: model, attachment: attachment)
        let persistedWithNote = model.board
        model.delete(note.id)
        model.finalizeDeferredDeletions(persistedBoard: persistedWithNote)
        #expect(exists(model, attachment.fileName))
        model.finalizeDeferredDeletions(persistedBoard: model.board)
        #expect(!exists(model, attachment.fileName))
    }

    @Test("No modo adiado, tirar a linha da nota também espera a gravação")
    func deferredUpdate() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeModel(directory, persistence: .deferred)
        let attachment = try #require(await model.prepareNoteImage(data: try pngData(), fileExtension: "png"))
        let note = makeNote(in: model, attachment: attachment)
        let persistedWithNote = model.board
        model.updateNote(note.id, title: "Nota", text: "só texto")
        model.finalizeDeferredDeletions(persistedBoard: persistedWithNote)
        #expect(exists(model, attachment.fileName))
        model.finalizeDeferredDeletions(persistedBoard: model.board)
        #expect(!exists(model, attachment.fileName))
    }
}
