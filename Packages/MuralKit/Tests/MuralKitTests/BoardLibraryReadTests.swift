import Foundation
import Testing

@testable import MuralKit

@Suite("Leitura de murais sem abri-los")
struct BoardLibraryReadTests {
    private let sticky = BoardItem(
        kind: .sticky, title: "Tinta", createdAt: Date(timeIntervalSinceReferenceDate: 1_000), position: BoardPoint(x: 40, y: 60),
        text: "Tinta azul")

    private func makeRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MuralLibraryRead-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Uma pasta que não existe, para conferir que ler não cria nada.
    private func missingRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MuralLibraryRead-\(UUID().uuidString)", isDirectory: true)
    }

    /// Cria um mural salvo e devolve a rota, o id e a pasta do pacote.
    private func createBoard(_ name: String, in library: BoardLibrary) async throws -> (route: BoardRoute, id: BoardID, package: URL) {
        let route = try await library.createNamedBoard(name)
        let id = try #require(route.savedID)
        let package = try await library.repository(for: route).packageURL(for: id)
        return (route, id, package)
    }

    /// Grava `board` no pacote do mural, numa revisão de conteúdo acima da atual.
    private func save(_ board: Board, to route: BoardRoute, in library: BoardLibrary) async throws {
        let snapshot = try #require(await library.open(route))
        var manifest = snapshot.manifest
        manifest.contentRevision += 1
        try await library.repository(for: route).save(
            BoardRepositorySnapshot(manifest: manifest, board: board, workspace: snapshot.workspace))
    }

    /// Caminho relativo → bytes de cada arquivo do pacote (as pastas entram com bytes vazios).
    private func contents(of package: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for path in try FileManager.default.subpathsOfDirectory(atPath: package.path) {
            let url = package.appendingPathComponent(path)
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                result[path + "/"] = Data()
            } else {
                result[path] = try Data(contentsOf: url)
            }
        }
        return result
    }

    // MARK: Murais salvos

    @Test("Um mural salvo volta pelo readBoard com o cartão gravado, e cada id lê o seu pacote")
    func savedBoardRoundTrips() async throws {
        let directory = try makeRoot()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let first = try await createBoard("Com cartão", in: library)
        let second = try await createBoard("Vazio", in: library)
        try await save(Board(items: [sticky]), to: first.route, in: library)

        #expect(try await library.readBoard(first.route) == Board(items: [sticky]))
        #expect(try await library.readBoard(second.route) == Board())
    }

    @Test("Ler o mural não altera nenhum arquivo do pacote")
    func readingDoesNotTouchThePackage() async throws {
        let directory = try makeRoot()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let created = try await createBoard("Intacto", in: library)
        try await save(Board(items: [sticky]), to: created.route, in: library)
        let before = try contents(of: created.package)

        _ = try await library.readBoard(created.route)

        #expect(try contents(of: created.package) == before)
    }

    @Test("Um id sem pacote devolve nil, sem criar pasta nenhuma")
    func unknownIDIsNil() async throws {
        let directory = missingRoot()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)

        #expect(try await library.readBoard(.saved(BoardID())) == nil)
        #expect(try await library.readBoard(.welcomeDraft(BoardID())) == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path), "nem a pasta da biblioteca foi criada")
    }

    @Test("Com a biblioteca criada, um id desconhecido devolve nil e não cria pacote")
    func unknownIDInAnExistingLibrary() async throws {
        let directory = try makeRoot()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        _ = try await createBoard("Existente", in: library)
        let boards = await library.boardsDirectory
        let before = try FileManager.default.contentsOfDirectory(atPath: boards.path).sorted()

        #expect(try await library.readBoard(.saved(BoardID())) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: boards.path).sorted() == before)
    }

    @Test("Um pacote sem board.json devolve nil")
    func packageWithoutBoardJSON() async throws {
        let directory = try makeRoot()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let created = try await createBoard("Sem board", in: library)
        try FileManager.default.removeItem(at: created.package.appendingPathComponent("board.json"))

        #expect(try await library.readBoard(created.route) == nil)
    }

    @Test("A rota da biblioteca não tem mural")
    func libraryRouteIsNil() async throws {
        let directory = missingRoot()
        let library = BoardLibrary(rootDirectory: directory)

        #expect(try await library.readBoard(.library) == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    // MARK: Arquivos ilegíveis

    @Test("board.json com formatVersion 999 lança futureBoardFormat e nenhum arquivo é tocado")
    func futureBoardFormatIsRefused() async throws {
        let directory = try makeRoot()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let created = try await createBoard("Do futuro", in: library)
        try Data(#"{"formatVersion":999,"items":[]}"#.utf8).write(to: created.package.appendingPathComponent("board.json"))
        let before = try contents(of: created.package)

        await #expect(throws: BoardRepositoryError.futureBoardFormat(999)) { try await library.readBoard(created.route) }
        #expect(try contents(of: created.package) == before)
    }

    @Test("A versão atual do formato e as anteriores são lidas")
    func currentAndOlderFormatsAreRead() async throws {
        let directory = try makeRoot()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let created = try await createBoard("Versões", in: library)

        for version in [0, 1, Board.currentFormatVersion] {
            try Data(#"{"formatVersion":\#(version),"items":[]}"#.utf8).write(to: created.package.appendingPathComponent("board.json"))
            let board = try #require(await library.readBoard(created.route))
            #expect(board.formatVersion == version && board.items.isEmpty)
        }
    }

    @Test("board.json ilegível lança corruptedBoard e o arquivo fica como estava")
    func corruptedBoardIsReported() async throws {
        let directory = try makeRoot()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let created = try await createBoard("Quebrado", in: library)
        try Data("not-json".utf8).write(to: created.package.appendingPathComponent("board.json"))
        let before = try contents(of: created.package)

        await #expect {
            try await library.readBoard(created.route)
        } throws: { error in
            guard case BoardRepositoryError.corruptedBoard = error else { return false }
            return true
        }
        #expect(try contents(of: created.package) == before)
    }

    @Test("Um view-state.json ilegível continua no lugar depois do readBoard; é o open que o põe em quarentena")
    func unreadableViewStateStaysInPlace() async throws {
        let directory = try makeRoot()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let created = try await createBoard("Estado ilegível", in: library)
        try await save(Board(items: [sticky]), to: created.route, in: library)
        let viewState = created.package.appendingPathComponent("view-state.json")
        try Data("not-json".utf8).write(to: viewState)
        let before = try contents(of: created.package)

        let board = try await library.readBoard(created.route)

        #expect(board == Board(items: [sticky]))
        #expect(try contents(of: created.package) == before, "nada foi movido, criado nem apagado")
        #expect(try Data(contentsOf: viewState) == Data("not-json".utf8))

        // Controle: abrir o mural é que move o arquivo ilegível para a quarentena e grava o estado padrão no lugar.
        _ = try await library.open(created.route)
        #expect(try Data(contentsOf: viewState) != Data("not-json".utf8))
        #expect(try contents(of: created.package).keys.contains { $0.hasPrefix("view-state-corrupt-") })
    }

    @Test("Depois da quarentena do view-state.json o mural abre de novo e continua na listagem")
    func quarantinedViewStateIsReplacedWithDefault() async throws {
        let directory = try makeRoot()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let created = try await createBoard("Estado ilegível", in: library)
        try await save(Board(items: [sticky]), to: created.route, in: library)
        let viewState = created.package.appendingPathComponent("view-state.json")
        try Data("not-json".utf8).write(to: viewState)

        let first = try #require(await library.open(created.route))
        #expect(FileManager.default.fileExists(atPath: viewState.path), "o estado padrão foi regravado")

        let second = try #require(await library.open(created.route))
        #expect(second.board == Board(items: [sticky]))
        #expect(second.workspace == first.workspace)
        #expect(try await library.listSavedReport().entries.map(\.route) == [created.route])
    }

    @Test("Um manifest.json ilegível também não impede a leitura do board.json")
    func unreadableManifestIsNotRead() async throws {
        let directory = try makeRoot()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let created = try await createBoard("Manifesto ilegível", in: library)
        try await save(Board(items: [sticky]), to: created.route, in: library)
        try Data("not-json".utf8).write(to: created.package.appendingPathComponent("manifest.json"))
        let before = try contents(of: created.package)

        #expect(try await library.readBoard(created.route) == Board(items: [sticky]))
        #expect(try contents(of: created.package) == before)
    }

    // MARK: Rascunho de exemplo

    @Test("O rascunho de exemplo, depois do bootstrap, é lido por .welcomeDraft(id) e é o mesmo que o open devolve")
    func welcomeDraftIsRead() async throws {
        let directory = try makeRoot()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let state = try await library.bootstrap()
        let route = BoardRoute.welcomeDraft(state.stableWelcomeID)

        let board = try #require(await library.readBoard(route))

        #expect(!board.items.isEmpty, "o exemplo traz cartões")
        #expect(try #require(await library.open(route)).board == board)
    }

    @Test("Não confere o estado do rascunho: lê o que estiver no disco, mesmo com o descarte pela metade")
    func draftLifecycleIsNotChecked() async throws {
        let directory = try makeRoot()
        defer { try? FileManager.default.removeItem(at: directory) }
        let initial = BoardLibrary(rootDirectory: directory)
        let state = try await initial.bootstrap()
        let expected = try #require(await initial.readBoard(.welcomeDraft(state.stableWelcomeID)))
        // O descarte marca o estado e falha antes de apagar o pacote: o rascunho já não está ativo, mas o arquivo continua lá.
        let failing = BoardLibrary(
            rootDirectory: directory, faultInjection: BoardLibraryFaultInjection(points: [.beforeDiscardCleanup]))
        await #expect(throws: BoardLibraryError.self) { try await failing.discardWelcomeDraft() }
        let route = BoardRoute.welcomeDraft(state.stableWelcomeID)
        await #expect(throws: BoardLibraryError.self) { _ = try await failing.open(route) }

        #expect(try await failing.readBoard(route) == expected)
    }

    @Test("Sem rascunho no disco, .welcomeDraft devolve nil em vez de erro")
    func missingDraftIsNil() async throws {
        let directory = try makeRoot()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let state = try await library.bootstrap()
        try await library.discardWelcomeDraft()

        #expect(try await library.readBoard(.welcomeDraft(state.stableWelcomeID)) == nil)
    }

    // MARK: Repositório

    @Test("O repositório lê o board.json sozinho, sem manifest.json nem view-state.json, e não cria nada")
    func repositoryReadsOnlyBoardJSON() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = BoardRepository(rootDirectory: root)
        let id = BoardID()
        let package = await repository.packageURL(for: id)
        #expect(try await repository.readBoard(id) == nil, "a pasta do pacote nem existe")

        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        #expect(try await repository.readBoard(id) == nil, "pacote sem board.json")

        let board = Board(items: [sticky])
        try JSONEncoder().encode(board).write(to: package.appendingPathComponent("board.json"))
        #expect(try await repository.readBoard(id) == board)
        #expect(try FileManager.default.contentsOfDirectory(atPath: package.path) == ["board.json"], "nada mais foi criado")
    }
}

extension BoardRoute {
    fileprivate var savedID: BoardID? {
        if case .saved(let id) = self { return id }
        return nil
    }
}
