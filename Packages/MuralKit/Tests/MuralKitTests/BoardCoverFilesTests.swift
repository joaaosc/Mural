import CoreGraphics
import Foundation
import Testing

@testable import MuralKit

/// Um UUID fixo, para os nomes escritos à mão nos argumentos dos testes.
private let fixedUUID = "0F0E0D0C-0B0A-0908-0706-050403020100"

@Suite("Arquivos de capa dos murais")
struct BoardCoverFilesTests {
    private let boardID = BoardID()

    private func makeFiles() -> BoardCoverFiles {
        BoardCoverFiles(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                "MuralCoverFiles-\(UUID().uuidString)", isDirectory: true))
    }

    private func contents(of files: BoardCoverFiles) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: files.directory.path)) ?? []).sorted()
    }

    /// Cria um arquivo com esse nome direto na pasta, sem passar por `store`.
    private func put(_ files: BoardCoverFiles, _ name: String) throws {
        try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: files.directory.appendingPathComponent(name))
    }

    private func name(_ id: BoardID, _ revision: Int) -> String {
        BoardCoverFiles.fileName(for: id, revision: revision)
    }

    // MARK: Imagens de teste

    /// Imagem de uma cor só, como a que o app desenharia.
    private func solidImage(width: Int = 64, height: Int = 40) throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    /// Imagem cheia de detalhes (quadradinhos de cores sorteadas, sempre as mesmas), para a qualidade do JPEG pesar no tamanho.
    private func busyImage(side: Int = 128) throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        var seed: UInt64 = 12_345
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 40) / Double(1 << 24)
        }
        for x in stride(from: 0, to: side, by: 4) {
            for y in stride(from: 0, to: side, by: 4) {
                context.setFillColor(red: next(), green: next(), blue: next(), alpha: 1)
                context.fill(CGRect(x: x, y: y, width: 4, height: 4))
            }
        }
        return try #require(context.makeImage())
    }

    /// Larga demais para o JPEG, que vai até 65 535 pontos de lado.
    private func tooWideImage() throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: 65_536, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 65_536, height: 1))
        return try #require(context.makeImage())
    }

    // MARK: Gravar e achar

    @Test("Grava a capa em JPEG, com o nome do mural e da revisão, e latest a acha")
    func storeWritesAJPEGAndLatestFindsIt() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }

        let cover = try files.store(try solidImage(width: 64, height: 40), for: boardID, revision: 3)

        #expect(cover.boardID == boardID && cover.revision == 3)
        #expect(cover.url == files.directory.appendingPathComponent("\(boardID.rawValue.uuidString)-r3.jpg"))
        let data = try Data(contentsOf: cover.url)
        #expect(TestImages.typeIdentifier(of: data) == "public.jpeg")
        let size = try #require(TestImages.size(of: data))
        #expect(size.width == 64 && size.height == 40)
        #expect(contents(of: files) == [cover.url.lastPathComponent])
        #expect(files.latest(for: boardID) == cover)
    }

    @Test("O nome é o UUID em maiúsculas, -r e a revisão, com a extensão .jpg")
    func fileNameFormat() throws {
        let id = BoardID(rawValue: try #require(UUID(uuidString: fixedUUID.lowercased())))
        #expect(BoardCoverFiles.fileName(for: id, revision: 12) == "\(fixedUUID)-r12.jpg")
        #expect(BoardCoverFiles.fileName(for: id, revision: 0) == "\(fixedUUID)-r0.jpg")
    }

    @Test("A pasta é criada, com as intermediárias, quando falta")
    func createsMissingDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MuralCoverRoot-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = BoardCoverFiles(directory: root.appendingPathComponent("a/b/Covers", isDirectory: true))

        let cover = try files.store(try solidImage(), for: boardID, revision: 1)

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: files.directory.path, isDirectory: &isDirectory) && isDirectory.boolValue)
        #expect(FileManager.default.fileExists(atPath: cover.url.path))
    }

    @Test("Revisão 0 é válida")
    func revisionZeroIsValid() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }

        let cover = try files.store(try solidImage(), for: boardID, revision: 0)

        #expect(files.latest(for: boardID) == cover)
        #expect(cover.url.lastPathComponent == "\(boardID.rawValue.uuidString)-r0.jpg")
    }

    @Test("A qualidade pedida chega ao JPEG: mais qualidade, arquivo maior; fora de 0 a 1 é limitada, sem erro")
    func qualityReachesTheEncoder() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let image = try busyImage()
        let low = BoardID()
        let high = BoardID()

        let lowSize = try Data(contentsOf: try files.store(image, for: low, revision: 1, quality: 0.1).url).count
        let highSize = try Data(contentsOf: try files.store(image, for: high, revision: 1, quality: 0.95).url).count
        #expect(highSize > lowSize, "0,95 gerou \(highSize) bytes e 0,1 gerou \(lowSize)")

        let tooHigh = try files.store(image, for: BoardID(), revision: 1, quality: 7)
        let tooLow = try files.store(image, for: BoardID(), revision: 1, quality: -3)
        #expect(try Data(contentsOf: tooHigh.url).count >= highSize)
        #expect(try Data(contentsOf: tooLow.url).count <= lowSize)
    }

    // MARK: Revisões

    @Test("Uma revisão nova apaga a anterior do mesmo mural e deixa as dos outros murais e os arquivos estranhos")
    func newRevisionReplacesOnlyTheSameBoard() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let image = try solidImage()
        let other = BoardID()
        let otherCover = try files.store(image, for: other, revision: 1)
        try put(files, "notas.txt")
        try put(files, ".oculto")
        let first = try files.store(image, for: boardID, revision: 1)

        let second = try files.store(image, for: boardID, revision: 2)

        #expect(!FileManager.default.fileExists(atPath: first.url.path))
        #expect(FileManager.default.fileExists(atPath: second.url.path))
        #expect(files.latest(for: boardID) == second)
        #expect(files.latest(for: other) == otherCover)
        #expect(contents(of: files) == [".oculto", name(boardID, 2), "notas.txt", name(other, 1)].sorted())
    }

    @Test("Gravar de novo a mesma revisão troca o arquivo, sem apagá-lo")
    func storingTheSameRevisionReplacesTheFile() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }

        try files.store(try solidImage(width: 64, height: 40), for: boardID, revision: 4)
        let again = try files.store(try solidImage(width: 32, height: 20), for: boardID, revision: 4)

        #expect(contents(of: files) == [again.url.lastPathComponent])
        let size = try #require(TestImages.size(of: try Data(contentsOf: again.url)))
        #expect(size.width == 32 && size.height == 20)
    }

    @Test("A última capa gravada fica, mesmo com revisão menor que a de antes")
    func lastStoredCoverWins() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let image = try solidImage()

        try files.store(image, for: boardID, revision: 5)
        let older = try files.store(image, for: boardID, revision: 3)

        #expect(contents(of: files) == [older.url.lastPathComponent])
        #expect(files.latest(for: boardID)?.revision == 3)
    }

    @Test("latest escolhe a maior revisão, comparada como número, entre arquivos postos à mão")
    func latestPicksTheHighestRevision() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        for revision in [2, 10, 9] { try put(files, name(boardID, revision)) }
        try put(files, name(BoardID(), 99))

        let latest = try #require(files.latest(for: boardID))

        #expect(latest.revision == 10, "r10 vale mais que r9, embora venha antes na ordem alfabética")
        #expect(latest.boardID == boardID)
        #expect(latest.url == files.directory.appendingPathComponent(name(boardID, 10)))
    }

    @Test("latest é nil para um mural sem capa e para uma pasta que não existe")
    func latestWithoutCovers() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        #expect(files.latest(for: boardID) == nil, "a pasta nem existe")
        #expect(!FileManager.default.fileExists(atPath: files.directory.path), "ler não cria a pasta")

        try files.store(try solidImage(), for: BoardID(), revision: 1)
        #expect(files.latest(for: boardID) == nil, "só há capa de outro mural")
    }

    @Test("latest ignora o que não tem nome de capa, mesmo com revisão mais alta")
    func latestIgnoresStrangeNames() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let uuid = boardID.rawValue.uuidString
        try put(files, name(boardID, 1))
        try put(files, "\(uuid)-r5.png")
        try put(files, ".\(uuid)-r6.jpg")
        try put(files, "\(uuid)-r-7.jpg")
        try put(files, "\(uuid)-rx.jpg")
        try put(files, "\(uuid.lowercased())-r8.jpg")
        try FileManager.default.createDirectory(
            at: files.directory.appendingPathComponent(name(boardID, 9)), withIntermediateDirectories: true)

        #expect(files.latest(for: boardID)?.revision == 1)
    }

    // MARK: Nomes

    @Test("parse devolve o mural e a revisão de um nome no padrão, e ele volta a ser o mesmo nome")
    func parseAcceptsCanonicalNames() throws {
        for revision in [0, 1, 42, Int.max] {
            let fileName = name(boardID, revision)
            let parsed = try #require(BoardCoverFiles.parse(fileName), "\(fileName)")
            #expect(parsed.boardID == boardID && parsed.revision == revision)
            #expect(BoardCoverFiles.fileName(for: parsed.boardID, revision: parsed.revision) == fileName)
        }
    }

    @Test(
        "parse recusa nomes fora do padrão",
        arguments: [
            "NAO-E-UM-UUID-r1.jpg", "\(fixedUUID)-r-1.jpg", "\(fixedUUID)-r1.png", "\(fixedUUID)-r1.JPG", "\(fixedUUID)-r1.jpeg",
            ".\(fixedUUID)-r1.jpg", "._\(fixedUUID)-r1.jpg", "\(fixedUUID)-r.jpg", "\(fixedUUID)-r1a.jpg", "\(fixedUUID)-r+1.jpg",
            "\(fixedUUID)-r 1.jpg", "\(fixedUUID)-r01.jpg", "\(fixedUUID)-r1.5.jpg", "\(fixedUUID)-r1-r2.jpg",
            "\(fixedUUID)-r99999999999999999999.jpg", "\(fixedUUID.lowercased())-r1.jpg", "\(fixedUUID)-1.jpg", "\(fixedUUID).jpg",
            "\(fixedUUID)-r1.jpg.tmp", "pasta/\(fixedUUID)-r1.jpg", "r1.jpg", "-r1.jpg", ".jpg", "",
        ])
    func parseRefusesStrangeNames(fileName: String) {
        #expect(BoardCoverFiles.parse(fileName) == nil, "\(fileName.debugDescription)")
    }

    // MARK: remove e sweep

    @Test("remove apaga todas as revisões do mural e deixa as dos outros")
    func removeDeletesEveryRevisionOfTheBoard() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let other = BoardID()
        for revision in [1, 2, 7] { try put(files, name(boardID, revision)) }
        try put(files, name(other, 1))
        try put(files, "notas.txt")

        files.remove(for: boardID)

        #expect(files.latest(for: boardID) == nil)
        #expect(contents(of: files) == [name(other, 1), "notas.txt"].sorted())
    }

    @Test("remove com a pasta inexistente não é erro e não cria a pasta")
    func removeWithMissingDirectory() {
        let files = makeFiles()
        files.remove(for: boardID)
        #expect(!FileManager.default.fileExists(atPath: files.directory.path))
    }

    @Test("sweep apaga as capas de murais fora da lista e deixa arquivos estranhos, ocultos e subpastas")
    func sweepRemovesCoversOfUnlistedBoards() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let image = try solidImage()
        let kept = BoardID()
        let goneA = BoardID()
        let goneB = BoardID()
        try files.store(image, for: kept, revision: 3)
        try files.store(image, for: goneA, revision: 1)
        try files.store(image, for: goneB, revision: 12)
        let strangers = [
            "notas.txt", ".oculto", ".\(goneA.rawValue.uuidString)-r9.jpg", "\(goneA.rawValue.uuidString)-r9.png",
            "\(goneA.rawValue.uuidString.lowercased())-r9.jpg",
        ]
        for stranger in strangers { try put(files, stranger) }
        let subfolder = files.directory.appendingPathComponent("Subpasta")
        let folderNamedLikeACover = files.directory.appendingPathComponent(name(goneB, 1))
        for folder in [subfolder, folderNamedLikeACover] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let before = contents(of: files)

        let removed = files.sweep(keeping: [kept])

        #expect(removed == [name(goneA, 1), name(goneB, 12)].sorted())
        #expect(contents(of: files) == before.filter { !removed.contains($0) })
        #expect(files.latest(for: kept)?.revision == 3)
        #expect(files.sweep(keeping: [kept]).isEmpty, "uma segunda passada não acha mais nada")
    }

    @Test("sweep com a lista vazia apaga todas as capas, e com todos os murais na lista não apaga nada")
    func sweepWithEmptyAndFullLists() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let image = try solidImage()
        let first = BoardID()
        let second = BoardID()
        try files.store(image, for: first, revision: 1)
        try files.store(image, for: second, revision: 2)

        #expect(files.sweep(keeping: [first, second]).isEmpty)
        #expect(contents(of: files).count == 2)
        #expect(files.sweep(keeping: []) == [name(first, 1), name(second, 2)].sorted())
        #expect(contents(of: files).isEmpty)
    }

    @Test("sweep com a pasta inexistente não é erro e não cria a pasta")
    func sweepWithMissingDirectory() {
        let files = makeFiles()
        #expect(files.sweep(keeping: [boardID]).isEmpty)
        #expect(files.sweep(keeping: []).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: files.directory.path))
    }

    // MARK: Erros

    @Test("Revisão negativa lança invalidRevision, sem criar a pasta")
    func negativeRevisionThrows() throws {
        let files = makeFiles()
        let image = try solidImage()

        #expect(throws: BoardCoverFilesError.invalidRevision) { try files.store(image, for: boardID, revision: -1) }
        #expect(throws: BoardCoverFilesError.invalidRevision) { try files.store(image, for: boardID, revision: Int.min) }
        #expect(!FileManager.default.fileExists(atPath: files.directory.path))
    }

    @Test("Uma imagem que o JPEG não comporta lança encodingFailed, sem criar a pasta nem apagar a capa anterior")
    func unencodableImageThrows() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let wide = try tooWideImage()
        #expect(throws: BoardCoverFilesError.encodingFailed) { try files.store(wide, for: boardID, revision: 1) }
        #expect(!FileManager.default.fileExists(atPath: files.directory.path))

        let existing = try files.store(try solidImage(), for: boardID, revision: 1)
        #expect(throws: BoardCoverFilesError.encodingFailed) { try files.store(wide, for: boardID, revision: 2) }
        #expect(files.latest(for: boardID) == existing)
    }

    @Test("Erro de disco é lançado: a pasta não pode ser criada porque o caminho é um arquivo")
    func diskErrorsAreThrown() throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("MuralCoverBlocker-\(UUID().uuidString)")
        try Data("arquivo".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let files = BoardCoverFiles(directory: blocker.appendingPathComponent("Covers", isDirectory: true))
        let image = try solidImage()

        #expect(throws: (any Error).self) { try files.store(image, for: boardID, revision: 1) }
        #expect(files.latest(for: boardID) == nil)
        #expect(files.sweep(keeping: []).isEmpty)
    }
}
