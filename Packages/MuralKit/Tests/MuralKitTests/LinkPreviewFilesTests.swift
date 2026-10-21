import CoreGraphics
import Foundation
import Testing

@testable import MuralKit

@Suite("Arquivos de prévia de links")
struct LinkPreviewFilesTests {
    private let itemID = UUID()

    private func makeFiles() -> LinkPreviewFiles {
        LinkPreviewFiles(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                "MuralPreviewFiles-\(UUID().uuidString)", isDirectory: true))
    }

    private func contents(of files: LinkPreviewFiles) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: files.directory.path)) ?? []).sorted()
    }

    private func read(_ files: LinkPreviewFiles, _ name: String?) throws -> Data {
        try Data(contentsOf: files.url(for: try #require(name)))
    }

    // MARK: Imagem de prévia

    @Test("Imagem de 2000x1000 vira 800x400 em JPEG, com a proporção mantida")
    func largeImageIsScaledDown() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }

        let names = try files.store(imageData: try TestImages.png(width: 2_000, height: 1_000), iconData: nil, for: itemID)

        let data = try read(files, names.image)
        #expect(names.icon == nil)
        #expect(names.image?.hasSuffix(".jpg") == true)
        #expect(TestImages.typeIdentifier(of: data) == "public.jpeg")
        let size = try #require(TestImages.size(of: data))
        #expect(size.width == 800 && size.height == 400)
        #expect(contents(of: files).count == 1)
    }

    @Test("O lado maior é que limita: imagem em pé de 1000x3000 vira 800 de altura")
    func tallImageIsLimitedByHeight() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }

        let names = try files.store(imageData: try TestImages.jpeg(width: 1_000, height: 3_000), iconData: nil, for: itemID)

        let size = try #require(TestImages.size(of: try read(files, names.image)))
        #expect(size.height == 800 && (266...267).contains(size.width))
    }

    @Test("Imagem menor que o limite não é ampliada")
    func smallImageIsNotEnlarged() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }

        let names = try files.store(imageData: try TestImages.png(width: 400, height: 300), iconData: nil, for: itemID)

        let size = try #require(TestImages.size(of: try read(files, names.image)))
        #expect(size.width == 400 && size.height == 300)
    }

    @Test("Imagem com transparência sai em PNG e mantém o canal alfa")
    func transparentImageIsPNG() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }

        let names = try files.store(imageData: try TestImages.png(width: 1_600, height: 800, transparent: true), iconData: nil, for: itemID)

        let data = try read(files, names.image)
        #expect(names.image?.hasSuffix(".png") == true)
        #expect(TestImages.typeIdentifier(of: data) == "public.png")
        #expect(TestImages.hasAlpha(data))
        let size = try #require(TestImages.size(of: data))
        #expect(size.width == 800 && size.height == 400)
    }

    @Test("Imagem sem transparência sai em JPEG, mesmo quando a origem é um PNG com canal alfa todo opaco")
    func opaqueImageIsJPEG() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let opaquePNG = try TestImages.png(width: 600, height: 300)
        #expect(TestImages.hasAlpha(opaquePNG), "controle: a origem declara canal alfa")

        let names = try files.store(imageData: opaquePNG, iconData: nil, for: itemID)

        let data = try read(files, names.image)
        #expect(names.image?.hasSuffix(".jpg") == true)
        #expect(TestImages.typeIdentifier(of: data) == "public.jpeg")
        #expect(!TestImages.hasAlpha(data))
    }

    @Test("A orientação gravada na foto é aplicada ao reduzir")
    func orientationIsApplied() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }

        // Orientação 6: a imagem armazenada em 400x200 é mostrada em pé, 200x400.
        let rotated = try files.store(imageData: try TestImages.jpeg(width: 400, height: 200, orientation: 6), iconData: nil, for: itemID)
        let size = try #require(TestImages.size(of: try read(files, rotated.image)))
        #expect(size.width == 200 && size.height == 400)

        // Orientação 8 com redução: 1600x800 armazenada vira 400x800 (e não 800x400).
        let reduced = try files.store(imageData: try TestImages.jpeg(width: 1_600, height: 800, orientation: 8), iconData: nil, for: itemID)
        let reducedSize = try #require(TestImages.size(of: try read(files, reduced.image)))
        #expect(reducedSize.width == 400 && reducedSize.height == 800)
    }

    @Test(
        "Imagem com lado menor que 32 px é descartada como provável pixel de rastreamento",
        arguments: [
            (32, 32, true), (32, 500, true), (500, 32, true), (31, 500, false), (500, 31, false), (31, 31, false), (20, 20, false),
            (1, 1, false),
        ])
    func tinyImagesAreDiscarded(width: Int, height: Int, kept: Bool) throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }

        let names = try files.store(imageData: try TestImages.png(width: width, height: height), iconData: nil, for: itemID)

        #expect((names.image != nil) == kept)
        #expect(contents(of: files).count == (kept ? 1 : 0))
        if !kept { #expect(!FileManager.default.fileExists(atPath: files.directory.path), "sem nada para gravar a pasta nem é criada") }
    }

    // MARK: Ícone

    @Test("Ícone de 512x512 vira 64x64 em PNG, com nome de ícone")
    func iconIsScaledToSixtyFour() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }

        let names = try files.store(imageData: nil, iconData: try TestImages.png(width: 512, height: 512), for: itemID)

        let data = try read(files, names.icon)
        #expect(names.image == nil)
        #expect(TestImages.typeIdentifier(of: data) == "public.png")
        let size = try #require(TestImages.size(of: data))
        #expect(size.width == 64 && size.height == 64)
        let pattern = try Regex("\(itemID.uuidString)-icon-[0-9A-Fa-f]{8}\\.png")
        #expect(names.icon?.wholeMatch(of: pattern) != nil, "\(String(describing: names.icon))")
    }

    @Test("Ícone retangular mantém a proporção e ícone opaco também sai em PNG")
    func iconKeepsProportionAndAlwaysPNG() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }

        let names = try files.store(imageData: nil, iconData: try TestImages.jpeg(width: 256, height: 128), for: itemID)

        let data = try read(files, names.icon)
        #expect(TestImages.typeIdentifier(of: data) == "public.png")
        let size = try #require(TestImages.size(of: data))
        #expect(size.width == 64 && size.height == 32)
    }

    @Test(
        "Ícone com lado menor que 16 px é descartado e o menor aceito fica no tamanho original",
        arguments: [
            (16, 16, true), (16, 64, true), (15, 15, false), (15, 64, false), (64, 15, false), (1, 1, false),
        ])
    func tinyIconsAreDiscarded(width: Int, height: Int, kept: Bool) throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }

        let names = try files.store(imageData: nil, iconData: try TestImages.png(width: width, height: height), for: itemID)

        #expect((names.icon != nil) == kept)
        if kept {
            let size = try #require(TestImages.size(of: try read(files, names.icon)))
            #expect(size.width == width && size.height == height)
        }
    }

    @Test("Os limites da imagem e do ícone são diferentes: 20x20 não é prévia, mas serve de ícone")
    func sameDataDifferentLimits() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let small = try TestImages.png(width: 20, height: 20)

        let names = try files.store(imageData: small, iconData: small, for: itemID)

        #expect(names.image == nil)
        #expect(names.icon != nil)
    }

    // MARK: Dados inválidos

    @Test(
        "Dados que não são imagem viram nil, sem erro e sem criar a pasta",
        arguments: [
            Data(), Data("isto não é uma imagem".utf8), Data("<html><body>erro 404</body></html>".utf8), Data((0...255).map { UInt8($0) }),
            Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), Data([0xFF, 0xD8, 0xFF]), Data(repeating: 0, count: 4_096),
        ])
    func invalidDataIsNil(data: Data) throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }

        let names = try files.store(imageData: data, iconData: data, for: itemID)

        #expect(names.image == nil && names.icon == nil)
        #expect(!FileManager.default.fileExists(atPath: files.directory.path))
    }

    @Test("Um dado inválido não impede o outro de ser gravado")
    func oneInvalidDoesNotBlockTheOther() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let garbage = Data("lixo".utf8)

        let imageOnly = try files.store(imageData: try TestImages.png(width: 100, height: 100), iconData: garbage, for: itemID)
        #expect(imageOnly.image != nil && imageOnly.icon == nil)

        let iconOnly = try files.store(imageData: garbage, iconData: try TestImages.png(width: 100, height: 100), for: itemID)
        #expect(iconOnly.image == nil && iconOnly.icon != nil)

        let both = try files.store(
            imageData: try TestImages.png(width: 100, height: 100), iconData: try TestImages.png(width: 100, height: 100), for: itemID)
        #expect(both.image != nil && both.icon != nil)
        #expect(contents(of: files).count == 4)
    }

    @Test("Sem dados nenhum, não grava nada")
    func nothingToStore() throws {
        let files = makeFiles()
        let names = try files.store(imageData: nil, iconData: nil, for: itemID)
        #expect(names.image == nil && names.icon == nil)
        #expect(!FileManager.default.fileExists(atPath: files.directory.path))
    }

    // MARK: Nomes e pasta

    @Test("Cada chamada grava nomes novos, no formato <itemID>-<8 hex>.jpg e <itemID>-icon-<8 hex>.png, sem apagar os anteriores")
    func namesAreVersionedAndUnique() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let image = try TestImages.png(width: 300, height: 200)
        let icon = try TestImages.png(width: 128, height: 128)

        var imageNames = Set<String>()
        var iconNames = Set<String>()
        for _ in 0..<20 {
            let names = try files.store(imageData: image, iconData: icon, for: itemID)
            imageNames.insert(try #require(names.image))
            iconNames.insert(try #require(names.icon))
        }

        #expect(imageNames.count == 20 && iconNames.count == 20)
        #expect(contents(of: files).count == 40)
        let imagePattern = try Regex("\(itemID.uuidString)-[0-9A-Fa-f]{8}\\.jpg")
        let iconPattern = try Regex("\(itemID.uuidString)-icon-[0-9A-Fa-f]{8}\\.png")
        #expect(imageNames.allSatisfy { $0.wholeMatch(of: imagePattern) != nil }, "\(imageNames.sorted())")
        #expect(iconNames.allSatisfy { $0.wholeMatch(of: iconPattern) != nil }, "\(iconNames.sorted())")
    }

    @Test("Cartões diferentes recebem nomes que começam pelo próprio id")
    func namesStartWithTheItemID() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let other = UUID()
        let image = try TestImages.png(width: 100, height: 100)

        let first = try files.store(imageData: image, iconData: nil, for: itemID)
        let second = try files.store(imageData: image, iconData: nil, for: other)

        #expect(first.image?.hasPrefix("\(itemID.uuidString)-") == true)
        #expect(second.image?.hasPrefix("\(other.uuidString)-") == true)
    }

    @Test("A pasta é criada, com as intermediárias, quando falta")
    func createsMissingDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MuralPreviewRoot-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = LinkPreviewFiles(directory: root.appendingPathComponent("a/b/Previews", isDirectory: true))

        let names = try files.store(imageData: try TestImages.png(width: 100, height: 100), iconData: nil, for: itemID)

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: files.directory.path, isDirectory: &isDirectory) && isDirectory.boolValue)
        #expect(FileManager.default.fileExists(atPath: files.url(for: try #require(names.image)).path))
    }

    @Test("Erro de disco é lançado: a pasta não pode ser criada porque o caminho é um arquivo")
    func diskErrorsAreThrown() throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("MuralPreviewBlocker-\(UUID().uuidString)")
        try Data("arquivo".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let files = LinkPreviewFiles(directory: blocker.appendingPathComponent("Previews", isDirectory: true))

        #expect(throws: (any Error).self) {
            try files.store(imageData: try TestImages.png(width: 100, height: 100), iconData: nil, for: itemID)
        }
        // Sem nada gravável, não há erro de disco a lançar.
        #expect(try files.store(imageData: Data("lixo".utf8), iconData: nil, for: itemID).image == nil)
    }

    @Test("url(for:) junta a pasta e o nome")
    func urlForFileName() {
        let files = makeFiles()
        #expect(files.url(for: "A.jpg") == files.directory.appendingPathComponent("A.jpg"))
        #expect(files.url(for: "A.jpg").deletingLastPathComponent().path == files.directory.path)
    }

    // MARK: sweep

    private func createFile(_ files: LinkPreviewFiles, _ name: String, age: TimeInterval, now: Date) throws {
        try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        let url = files.url(for: name)
        try Data("x".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
    }

    @Test("sweep apaga só o que nenhum cartão usa e é mais antigo que a idade mínima")
    func sweepRemovesOnlyUnreferencedOldFiles() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try createFile(files, "usado-antigo.jpg", age: 3_600, now: now)
        try createFile(files, "orfao-antigo.jpg", age: 3_600, now: now)
        try createFile(files, "orfao-antigo-2.png", age: 86_400, now: now)
        try createFile(files, "orfao-recente.png", age: 60, now: now)
        try createFile(files, "orfao-no-limite.png", age: 600, now: now)
        try createFile(files, "orfao-do-futuro.png", age: -3_600, now: now)

        let removed = files.sweep(keeping: ["usado-antigo.jpg"], now: now)

        #expect(removed == ["orfao-antigo-2.png", "orfao-antigo.jpg"])
        #expect(contents(of: files) == ["orfao-do-futuro.png", "orfao-no-limite.png", "orfao-recente.png", "usado-antigo.jpg"])
        #expect(files.sweep(keeping: ["usado-antigo.jpg"], now: now).isEmpty, "uma segunda passada não acha mais nada")
    }

    @Test("A idade mínima e a data de referência são ajustáveis, e só 'mais antigo que' conta")
    func sweepHonorsMinimumAgeAndNow() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try createFile(files, "dez-minutos.png", age: 600, now: now)
        try createFile(files, "uma-hora.png", age: 3_600, now: now)

        #expect(files.sweep(keeping: [], minimumAge: 600, now: now) == ["uma-hora.png"])
        #expect(files.sweep(keeping: [], minimumAge: 600, now: now.addingTimeInterval(0.5)) == ["dez-minutos.png"])
    }

    @Test("sweep sem idade mínima apaga tudo que não é usado, mas deixa subpastas e arquivos ocultos")
    func sweepIgnoresDirectoriesAndHiddenFiles() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try createFile(files, "a.jpg", age: 10, now: now)
        try createFile(files, "b.png", age: 10, now: now)
        try createFile(files, ".oculto", age: 99_999, now: now)
        let subdirectory = files.url(for: "Subpasta")
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-99_999)], ofItemAtPath: subdirectory.path)

        #expect(files.sweep(keeping: ["b.png"], minimumAge: 0, now: now) == ["a.jpg"])
        #expect(contents(of: files) == [".oculto", "Subpasta", "b.png"])
    }

    @Test("Arquivo recém-gravado por store não é apagado pelo sweep padrão, mesmo sem cartão que o use")
    func freshFilesSurviveTheDefaultSweep() throws {
        let files = makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        let names = try files.store(
            imageData: try TestImages.png(width: 100, height: 100), iconData: try TestImages.png(width: 100, height: 100), for: itemID)

        #expect(files.sweep(keeping: []).isEmpty)
        #expect(contents(of: files).count == 2)
        // Passado o prazo, o mesmo arquivo sem uso é recolhido.
        #expect(
            files.sweep(keeping: [], now: .now.addingTimeInterval(601)).sorted()
                == [try #require(names.icon), try #require(names.image)].sorted())
    }

    @Test("Pasta que não existe não é erro e não é criada pelo sweep")
    func sweepWithMissingDirectory() {
        let files = makeFiles()
        #expect(files.sweep(keeping: ["x.png"]).isEmpty)
        #expect(files.sweep(keeping: [], minimumAge: 0, now: .distantFuture).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: files.directory.path))
    }
}
