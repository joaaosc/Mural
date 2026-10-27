import Foundation
import Testing

@testable import MuralKit

@Suite("Cópia do pacote no iCloud Drive")
struct BoardPackageMirrorTests {
    private let past = Date(timeIntervalSince1970: 1_600_000_000)
    private let documents = ["manifest.json", "board.json", "view-state.json"]

    /// Pastas temporárias: a biblioteca onde os murais são montados e a pasta que faz o papel do iCloud Drive.
    private struct Workspace {
        let root: URL
        let library: BoardLibrary
        let drive: URL

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func makeWorkspace() throws -> Workspace {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MuralMirror-\(UUID().uuidString)", isDirectory: true)
        let drive = root.appendingPathComponent("Drive", isDirectory: true)
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        return Workspace(root: root, library: BoardLibrary(rootDirectory: root.appendingPathComponent("Library")), drive: drive)
    }

    /// Um pacote de origem montado como o app faz: `exportPackage` de um mural salvo com uma imagem de verdade em `Items/`.
    private func exportBoard(named name: String, in library: BoardLibrary) async throws -> (package: URL, id: BoardID) {
        let route = try await library.createNamedBoard(name)
        guard case .saved(let id) = route else { throw BoardLibraryError.unavailableRoute(route) }
        let repository = try await library.repository(for: route)
        let folder = UUID()
        let board = Board(items: [
            BoardItem(id: folder, kind: .folder, title: "Assets", position: BoardPoint(x: 1, y: 2)),
            BoardItem(
                id: UUID(), kind: .image, title: "Image", parentID: folder, position: BoardPoint(x: 3, y: 4), fileName: "image.png"),
        ])
        try await repository.save(
            BoardRepositorySnapshot(
                manifest: BoardManifest(id: id, name: name, contentRevision: 1), board: board,
                workspace: BoardWorkspaceState(contentRevision: 1)))
        let items = await repository.packageURL(for: id).appendingPathComponent("Items", isDirectory: true)
        try Data([1, 2, 3, 4]).write(to: items.appendingPathComponent("image.png"))
        return (try await library.exportPackage(route), id)
    }

    /// Caminho relativo → bytes de cada arquivo comum do pacote.
    private func contents(of package: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for relative in try FileManager.default.subpathsOfDirectory(atPath: package.path) {
            let url = package.appendingPathComponent(relative)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                result[relative] = try Data(contentsOf: url)
            }
        }
        return result
    }

    private func modificationDate(of url: URL) throws -> Date {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require(attributes[.modificationDate] as? Date)
    }

    /// Recua a data de modificação: qualquer regravação depois disso fica visível.
    private func backdate(_ urls: [URL]) throws {
        for url in urls {
            try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: url.path)
        }
    }

    /// Muda os bytes do `board.json` da origem, como uma edição do mural faria.
    private func changeBoard(in package: URL) throws {
        let url = package.appendingPathComponent("board.json")
        try (try Data(contentsOf: url) + Data("\n".utf8)).write(to: url)
    }

    private func encodedManifest(_ manifest: BoardManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate)
        }
        return try encoder.encode(manifest)
    }

    @Test("Destino ausente: o pacote é criado igual à origem")
    func createsAnIdenticalPackage() async throws {
        let workspace = try makeWorkspace()
        defer { workspace.remove() }
        let (source, _) = try await exportBoard(named: "Original", in: workspace.library)
        let destination = workspace.drive.appendingPathComponent("Original.mural", isDirectory: true)

        let outcome = try BoardPackageMirror.sync(from: source, to: destination)

        #expect(outcome == .init(createdPackage: true, rewrittenFiles: 3, addedItems: 1, removedItems: 0))
        #expect(outcome.changedAnything)
        let copy = try contents(of: destination)
        #expect(Set(copy.keys) == ["manifest.json", "board.json", "view-state.json", "Items/image.png"])
        #expect(try copy == contents(of: source))
    }

    @Test("Segunda chamada sem mudança não grava nada e não mexe nas datas dos JSON")
    func secondCallChangesNothing() async throws {
        let workspace = try makeWorkspace()
        defer { workspace.remove() }
        let (source, _) = try await exportBoard(named: "Original", in: workspace.library)
        let destination = workspace.drive.appendingPathComponent("Original.mural", isDirectory: true)
        _ = try BoardPackageMirror.sync(from: source, to: destination)
        let documentURLs = documents.map { destination.appendingPathComponent($0) }
        try backdate(documentURLs)

        let outcome = try BoardPackageMirror.sync(from: source, to: destination)

        #expect(outcome == .init())
        #expect(!outcome.changedAnything)
        for url in documentURLs {
            #expect(try modificationDate(of: url) == past, "\(url.lastPathComponent) foi regravado")
        }
    }

    @Test("Um item a mais na origem: só ele é copiado, e só os JSON que mudaram são regravados")
    func copiesOnlyTheNewItem() async throws {
        let workspace = try makeWorkspace()
        defer { workspace.remove() }
        let (source, _) = try await exportBoard(named: "Original", in: workspace.library)
        let destination = workspace.drive.appendingPathComponent("Original.mural", isDirectory: true)
        _ = try BoardPackageMirror.sync(from: source, to: destination)
        let untouched = documents.map { destination.appendingPathComponent($0) } + [destination.appendingPathComponent("Items/image.png")]
        try backdate(untouched)
        try Data([9, 9]).write(to: source.appendingPathComponent("Items/extra.png"))
        try changeBoard(in: source)

        let outcome = try BoardPackageMirror.sync(from: source, to: destination)

        #expect(outcome == .init(createdPackage: false, rewrittenFiles: 1, addedItems: 1, removedItems: 0))
        #expect(try Data(contentsOf: destination.appendingPathComponent("Items/extra.png")) == Data([9, 9]))
        #expect(try modificationDate(of: destination.appendingPathComponent("Items/image.png")) == past, "a imagem foi copiada de novo")
        #expect(try modificationDate(of: destination.appendingPathComponent("manifest.json")) == past)
        #expect(try modificationDate(of: destination.appendingPathComponent("view-state.json")) == past)
        #expect(try modificationDate(of: destination.appendingPathComponent("board.json")) != past)
        #expect(try contents(of: destination) == contents(of: source))
    }

    @Test("Um item a menos na origem: o arquivo sai do destino")
    func removesItemsThatLeftTheSource() async throws {
        let workspace = try makeWorkspace()
        defer { workspace.remove() }
        let (source, _) = try await exportBoard(named: "Original", in: workspace.library)
        let destination = workspace.drive.appendingPathComponent("Original.mural", isDirectory: true)
        _ = try BoardPackageMirror.sync(from: source, to: destination)
        try FileManager.default.removeItem(at: source.appendingPathComponent("Items/image.png"))
        try changeBoard(in: source)

        let outcome = try BoardPackageMirror.sync(from: source, to: destination)

        #expect(outcome == .init(createdPackage: false, rewrittenFiles: 1, addedItems: 0, removedItems: 1))
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("Items/image.png").path))
        #expect(try contents(of: destination) == contents(of: source))
    }

    @Test("Destino com o manifesto de outro mural nunca é sobrescrito")
    func refusesAnotherBoardsPackage() async throws {
        let workspace = try makeWorkspace()
        defer { workspace.remove() }
        let (source, _) = try await exportBoard(named: "Original", in: workspace.library)
        let (other, otherID) = try await exportBoard(named: "Outro", in: workspace.library)
        let destination = workspace.drive.appendingPathComponent("Original.mural", isDirectory: true)
        _ = try BoardPackageMirror.sync(from: other, to: destination)
        let before = try contents(of: destination)
        try backdate(documents.map { destination.appendingPathComponent($0) })

        #expect(throws: BoardPackageMirrorError.destinationIsAnotherBoard(otherID)) {
            _ = try BoardPackageMirror.sync(from: source, to: destination)
        }

        #expect(try contents(of: destination) == before)
        for name in documents {
            #expect(try modificationDate(of: destination.appendingPathComponent(name)) == past, "\(name) foi regravado")
        }
    }

    @Test("Destino de outro mural em formato mais novo que o desta versão também nunca é sobrescrito")
    func refusesAnotherBoardsPackageOfANewerFormat() async throws {
        let workspace = try makeWorkspace()
        defer { workspace.remove() }
        let (source, _) = try await exportBoard(named: "Original", in: workspace.library)
        let otherID = BoardID()
        let destination = workspace.drive.appendingPathComponent("Original.mural", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let newer = BoardManifest(id: otherID, name: "Outro", schemaVersion: BoardManifest.currentSchemaVersion + 1)
        try encodedManifest(newer).write(to: destination.appendingPathComponent("manifest.json"))
        let before = try contents(of: destination)

        #expect(throws: BoardPackageMirrorError.destinationIsAnotherBoard(otherID)) {
            _ = try BoardPackageMirror.sync(from: source, to: destination)
        }

        #expect(try contents(of: destination) == before)
    }

    @Test("Destino que é um arquivo: recusado, e o arquivo fica")
    func refusesADestinationThatIsAFile() async throws {
        let workspace = try makeWorkspace()
        defer { workspace.remove() }
        let (source, _) = try await exportBoard(named: "Original", in: workspace.library)
        let destination = workspace.drive.appendingPathComponent("Original.mural")
        try Data("arquivo".utf8).write(to: destination)

        #expect(throws: BoardPackageMirrorError.destinationNotAPackage(destination)) {
            _ = try BoardPackageMirror.sync(from: source, to: destination)
        }

        #expect(try Data(contentsOf: destination) == Data("arquivo".utf8))
    }

    @Test("Origem incompleta é recusada e o destino não é criado", arguments: ["manifest.json", "board.json", "view-state.json", "Items"])
    func refusesAnIncompleteSource(missing: String) async throws {
        let workspace = try makeWorkspace()
        defer { workspace.remove() }
        let (source, _) = try await exportBoard(named: "Original", in: workspace.library)
        let destination = workspace.drive.appendingPathComponent("Original.mural", isDirectory: true)
        try FileManager.default.removeItem(at: source.appendingPathComponent(missing))

        #expect(throws: BoardPackageMirrorError.sourceIncomplete(source)) {
            _ = try BoardPackageMirror.sync(from: source, to: destination)
        }

        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test("A pasta que vai conter o pacote precisa existir: erro de arquivo, e nada é criado")
    func doesNotCreateTheFolderAboveThePackage() async throws {
        let workspace = try makeWorkspace()
        defer { workspace.remove() }
        let (source, _) = try await exportBoard(named: "Original", in: workspace.library)
        let missingFolder = workspace.drive.appendingPathComponent("Ausente", isDirectory: true)

        #expect {
            _ = try BoardPackageMirror.sync(from: source, to: missingFolder.appendingPathComponent("Original.mural", isDirectory: true))
        } throws: { error in
            guard case .io = error as? BoardPackageMirrorError else { return false }
            return true
        }

        #expect(!FileManager.default.fileExists(atPath: missingFolder.path))
    }

    @Test(
        "Falha no meio: o pacote que a chamada criou não fica para trás, mas a cópia que já existia fica",
        .disabled(if: getuid() == 0, "o root ignora permissões de arquivo"))
    func removesOnlyThePackageItCreated() async throws {
        let workspace = try makeWorkspace()
        defer { workspace.remove() }
        let (source, _) = try await exportBoard(named: "Original", in: workspace.library)
        let destination = workspace.drive.appendingPathComponent("Original.mural", isDirectory: true)
        let board = source.appendingPathComponent("board.json")

        // Pacote novo: o `board.json` ilegível derruba a cópia depois de a pasta ser criada.
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: board.path)
        #expect {
            _ = try BoardPackageMirror.sync(from: source, to: destination)
        } throws: { error in
            guard case .io = error as? BoardPackageMirrorError else { return false }
            return true
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))

        // Cópia que já existia: a falha deixa o que estava lá.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: board.path)
        _ = try BoardPackageMirror.sync(from: source, to: destination)
        try changeBoard(in: source)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: board.path)
        #expect {
            _ = try BoardPackageMirror.sync(from: source, to: destination)
        } throws: { error in
            guard case .io = error as? BoardPackageMirrorError else { return false }
            return true
        }
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("manifest.json").path))
    }

    @Test("Arquivo oculto, nome inseguro, subpasta e o que não é da cópia ficam como estão")
    func leavesUnmanagedEntriesAlone() async throws {
        let workspace = try makeWorkspace()
        defer { workspace.remove() }
        let (source, _) = try await exportBoard(named: "Original", in: workspace.library)
        let destination = workspace.drive.appendingPathComponent("Original.mural", isDirectory: true)
        _ = try BoardPackageMirror.sync(from: source, to: destination)
        let destinationItems = destination.appendingPathComponent("Items", isDirectory: true)
        try Data("a".utf8).write(to: destinationItems.appendingPathComponent(".DS_Store"))
        try Data("b".utf8).write(to: destinationItems.appendingPathComponent("a:b.png"))
        try FileManager.default.createDirectory(at: destinationItems.appendingPathComponent("Sub"), withIntermediateDirectories: false)
        try Data("c".utf8).write(to: destination.appendingPathComponent("LEIAME.txt"))
        // Do lado da origem, o oculto e o nome inseguro também não são copiados.
        let sourceItems = source.appendingPathComponent("Items", isDirectory: true)
        try Data("d".utf8).write(to: sourceItems.appendingPathComponent(".oculto"))
        try Data("e".utf8).write(to: sourceItems.appendingPathComponent("c:d.png"))
        let before = try contents(of: destination)

        let outcome = try BoardPackageMirror.sync(from: source, to: destination)

        #expect(!outcome.changedAnything)
        #expect(try contents(of: destination) == before)
        #expect(FileManager.default.fileExists(atPath: destinationItems.appendingPathComponent("Sub").path))
        #expect(!FileManager.default.fileExists(atPath: destinationItems.appendingPathComponent(".oculto").path))
        #expect(!FileManager.default.fileExists(atPath: destinationItems.appendingPathComponent("c:d.png").path))
    }

    @Test("Manifesto ilegível no destino é cópia danificada: tudo é regravado")
    func rewritesADamagedCopy() async throws {
        let workspace = try makeWorkspace()
        defer { workspace.remove() }
        let (source, _) = try await exportBoard(named: "Original", in: workspace.library)
        let destination = workspace.drive.appendingPathComponent("Original.mural", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        try Data("{ isto não é json".utf8).write(to: destination.appendingPathComponent("manifest.json"))

        let outcome = try BoardPackageMirror.sync(from: source, to: destination)

        #expect(outcome == .init(createdPackage: false, rewrittenFiles: 3, addedItems: 1, removedItems: 0))
        #expect(try contents(of: destination) == contents(of: source))
    }

    @Test("manifest(ofPackageAt:) lê o id e o nome; sem manifesto ou de formato futuro, é ilegível")
    func readsOnlyTheManifest() async throws {
        let workspace = try makeWorkspace()
        defer { workspace.remove() }
        let (source, id) = try await exportBoard(named: "Original", in: workspace.library)

        let manifest = try BoardPackageMirror.manifest(ofPackageAt: source)
        #expect(manifest.id == id)
        #expect(manifest.name == "Original")

        let empty = workspace.drive.appendingPathComponent("Vazio.mural", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: false)
        #expect {
            _ = try BoardPackageMirror.manifest(ofPackageAt: empty)
        } throws: { error in
            guard case .unreadableManifest = error as? BoardPackageMirrorError else { return false }
            return true
        }

        let future = workspace.drive.appendingPathComponent("Futuro.mural", isDirectory: true)
        try FileManager.default.createDirectory(at: future, withIntermediateDirectories: false)
        let futureManifest = BoardManifest(id: id, name: "Futuro", schemaVersion: BoardManifest.currentSchemaVersion + 1)
        try encodedManifest(futureManifest).write(to: future.appendingPathComponent("manifest.json"))
        #expect {
            _ = try BoardPackageMirror.manifest(ofPackageAt: future)
        } throws: { error in
            guard case .unreadableManifest = error as? BoardPackageMirrorError else { return false }
            return true
        }
    }
}
