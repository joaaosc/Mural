import Foundation
import Testing

@testable import MuralKit

@Suite("Versão do formato do mural")
struct BoardFormatVersionTests {
    // Ordem da lista: `child` dentro de `folder`; `note` e `otherFolder` soltos.
    let folder = BoardItem(kind: .folder, title: "Pasta", position: BoardPoint(x: 100, y: 100))
    let child: BoardItem
    let otherFolder = BoardItem(kind: .folder, title: "Outra pasta", position: BoardPoint(x: 400, y: 100))
    let note = BoardItem(kind: .text, title: "Nota", position: BoardPoint(x: 100, y: 400))
    let items: [BoardItem]

    init() {
        child = BoardItem(kind: .sticky, title: "Dentro da pasta", parentID: folder.id)
        items = [folder, child, otherFolder, note]
    }

    private func temporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MuralFormat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// O mural como uma build antiga o gravou: lido de um JSON com `formatVersion` 0.
    private func olderBoard() throws -> Board {
        let encoded = try JSONEncoder().encode(Board(items: items))
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["formatVersion"] = 0
        let board = try JSONDecoder().decode(Board.self, from: JSONSerialization.data(withJSONObject: object))
        try #require(board.formatVersion == 0)
        return board
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

    // MARK: Board

    @Test("Cada alteração de fato grava a versão que o conteúdo exige")
    func effectiveMutationsStampRequiredVersion() throws {
        let extra = BoardItem(kind: .sticky, title: "Novo", position: BoardPoint(x: 300, y: 300))
        var renamed = note
        renamed.title = "Outro título"
        let mutations: [(name: String, apply: (inout Board) -> Void)] = [
            ("add", { $0.add(extra) }),
            ("update", { $0.update(renamed) }),
            ("remove", { $0.remove(id: note.id) }),
            ("move", { $0.move(id: note.id, to: BoardPoint(x: 5, y: 5)) }),
            ("setPositions", { $0.setPositions([note.id: BoardPoint(x: 9, y: 9)]) }),
            ("remove de pasta com cartões", { $0.remove(id: folder.id) }),
            ("moveIntoFolder", { $0.moveIntoFolder(id: note.id, folderID: otherFolder.id) }),
            ("moveIntoFolder de pasta em pasta", { $0.moveIntoFolder(id: otherFolder.id, folderID: folder.id) }),
            ("moveIntoFolder de cartão de uma pasta para outra", { $0.moveIntoFolder(id: child.id, folderID: otherFolder.id) }),
            ("moveToBoard", { $0.moveToBoard(id: child.id, at: BoardPoint(x: 7, y: 7)) }),
            ("placeInFolder", { $0.placeInFolder(id: child.id, at: BoardPoint(x: 0, y: 40)) }),
        ]
        for mutation in mutations {
            let older = try olderBoard()
            var board = older
            mutation.apply(&board)
            #expect(board.items != older.items, "\(mutation.name) não alterou o mural")
            #expect(board.formatVersion == board.requiredFormatVersion, "\(mutation.name) não gravou a versão exigida")
            #expect(board.formatVersion >= 1, "\(mutation.name) deixou a versão antiga")
        }
    }

    @Test("A versão exigida vem do conteúdo: 2 com pasta dentro de pasta, 3 com link, 4 com cor, e volta sem eles")
    func requiredVersionFollowsContent() {
        #expect(Board().formatVersion == 1)
        #expect(Board(items: items).requiredFormatVersion == 1, "pasta solta com cartão dentro é da versão 1")

        var board = Board(items: items)
        let nested = board.moveIntoFolder(id: otherFolder.id, folderID: folder.id)
        #expect(nested)
        #expect(board.formatVersion == 2)
        #expect(Board(items: board.items).formatVersion == 2)

        let loose = board.moveToBoard(id: otherFolder.id, at: BoardPoint(x: 400, y: 100))
        #expect(loose)
        #expect(board.formatVersion == 1, "sem pasta aninhada, o mural volta a abrir nas builds da versão 1")

        var colored = note
        colored.colorTag = .green
        board.update(colored)
        #expect(board.formatVersion == 4, "cartão com cor exige a versão 4")
        #expect(Board(items: board.items).formatVersion == 4)

        board.update(note)
        #expect(board.formatVersion == 1, "sem cor, o mural volta a abrir nas builds da versão 1")

        board.add(BoardItem(kind: .link, title: "Apple", position: BoardPoint(x: 600, y: 100)))
        #expect(board.formatVersion == 3, "cartão de link exige a versão 3")

        board.update(colored)
        #expect(board.formatVersion == 4, "link e cor juntos exigem a versão 4")
        board.update(note)
        #expect(board.formatVersion == 3, "sem a cor, o link continua exigindo a versão 3")
    }

    @Test("Chamada sem efeito deixa o mural antigo, e a versão 0, como estavam")
    func ineffectiveCallsKeepOlderVersion() throws {
        let stranger = BoardItem(kind: .text, title: "De fora")
        let calls: [(name: String, apply: (inout Board) -> Void)] = [
            ("update de id desconhecido", { $0.update(stranger) }),
            ("remove de id desconhecido", { $0.remove(id: UUID()) }),
            ("move de cartão de pasta", { $0.move(id: child.id, to: BoardPoint(x: 5, y: 5)) }),
            ("move de id desconhecido", { $0.move(id: UUID(), to: BoardPoint(x: 5, y: 5)) }),
            ("setPositions vazio", { $0.setPositions([:]) }),
            ("setPositions na posição que já era", { $0.setPositions([note.id: note.position]) }),
            ("setPositions só de cartão de pasta e de id desconhecido", { $0.setPositions([child.id: .zero, UUID(): .zero]) }),
            ("moveIntoFolder de pasta dentro de si mesma", { $0.moveIntoFolder(id: folder.id, folderID: folder.id) }),
            ("moveIntoFolder para a pasta que já é o pai", { $0.moveIntoFolder(id: child.id, folderID: folder.id) }),
            ("moveIntoFolder para um destino que não é pasta", { $0.moveIntoFolder(id: note.id, folderID: child.id) }),
            ("moveToBoard de cartão que já está solto", { $0.moveToBoard(id: note.id, at: BoardPoint(x: 5, y: 5)) }),
            ("placeInFolder de cartão solto", { $0.placeInFolder(id: note.id, at: BoardPoint(x: 0, y: 40)) }),
            ("placeInFolder de id desconhecido", { $0.placeInFolder(id: UUID(), at: BoardPoint(x: 0, y: 40)) }),
        ]
        for call in calls {
            let older = try olderBoard()
            var board = older
            call.apply(&board)
            #expect(board == older, "\(call.name) alterou o mural")
            #expect(board.formatVersion == 0, "\(call.name) mexeu na versão")
        }
    }

    // MARK: Repositório

    /// Grava um mural da versão pedida e devolve o repositório, o id e a pasta do pacote.
    private func repositoryHolding(version: Int, in root: URL) async throws -> (repository: BoardRepository, id: BoardID, package: URL) {
        let repository = BoardRepository(rootDirectory: root)
        let id = BoardID()
        var board = Board(items: items)
        board.formatVersion = version
        try await repository.save(id: id, board: board, workspace: .default, manifest: BoardManifest(id: id, contentRevision: 1))
        return (repository, id, await repository.packageURL(for: id))
    }

    @Test("Mural de uma versão mais nova não abre, e nenhum arquivo é tocado")
    func futureBoardIsRefusedWithoutTouchingFiles() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let future = Board.currentFormatVersion + 1
        let (repository, id, package) = try await repositoryHolding(version: future, in: root)
        // Um view-state ilegível iria para a quarentena se a trava viesse depois da leitura dele.
        try Data("not-json".utf8).write(to: package.appendingPathComponent("view-state.json"))
        let before = try contents(of: package)

        await #expect(throws: BoardRepositoryError.futureBoardFormat(future)) { try await repository.load(id) }
        #expect(try contents(of: package) == before)
    }

    @Test("A exportação também recusa o mural de uma versão mais nova")
    func exportRefusesFutureBoard() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = BoardLibrary(rootDirectory: root)
        let route = try await library.createNamedBoard("Do futuro")
        let id = try #require(route.id)
        let repository = try await library.repository(for: route)
        let future = Board.currentFormatVersion + 1
        var board = Board(items: items)
        board.formatVersion = future
        try await repository.save(
            id: id, board: board, workspace: .default, manifest: BoardManifest(id: id, name: "Do futuro", contentRevision: 1))
        let before = try contents(of: await repository.packageURL(for: id))

        await #expect(throws: BoardRepositoryError.futureBoardFormat(future)) { try await library.exportPackage(route) }
        #expect(try contents(of: await repository.packageURL(for: id)) == before)
        let transfers = await library.transfersDirectory
        #expect(try FileManager.default.contentsOfDirectory(atPath: transfers.path).isEmpty)
    }

    @Test("A versão atual e as anteriores abrem normalmente")
    func currentAndOlderVersionsOpen() async throws {
        for version in [0, Board.currentFormatVersion] {
            let root = try temporaryRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let (repository, id, _) = try await repositoryHolding(version: version, in: root)
            let result = try #require(await repository.load(id))
            #expect(result.snapshot.board.formatVersion == version)
            #expect(result.snapshot.board.items == items)
        }
    }

    @Test("Mural antigo só sobe de versão com uma alteração real, e a gravação seguinte passa")
    func olderBoardUpgradesWithARealEdit() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (repository, id, _) = try await repositoryHolding(version: 0, in: root)
        let loaded = try #require(await repository.load(id)).snapshot
        let session = BoardSession(snapshot: loaded, repository: repository)

        // Sem alteração (id desconhecido): não há revisão nova nem o que gravar.
        var untouched = loaded.board
        untouched.update(BoardItem(kind: .text, title: "De fora"))
        try await session.update(board: untouched)
        #expect(await session.isDirty == false)
        _ = try await session.flush()
        #expect(try #require(await repository.load(id)).snapshot.board.formatVersion == 0)

        // Alteração real: a versão sobe junto com a revisão, e o mesmo snapshot grava de novo sem conflito.
        var edited = loaded.board
        edited.add(BoardItem(kind: .sticky, title: "Novo", position: BoardPoint(x: 300, y: 300)))
        try await session.update(board: edited)
        let saved = try await session.flush()
        let reloaded = try #require(await repository.load(id)).snapshot
        #expect(reloaded.board == edited)
        #expect(reloaded.board.formatVersion == 1, "o conteúdo continua sendo da versão 1")
        #expect(reloaded.manifest.contentRevision == loaded.manifest.contentRevision + 1)
        try await repository.save(saved)
    }

    @Test("A mensagem diz que o mural veio de uma versão mais nova e que nada foi alterado")
    func futureBoardMessage() {
        let future = Board.currentFormatVersion + 1
        #expect(
            BoardRepositoryError.futureBoardFormat(future).errorDescription
                == "Este mural foi salvo por uma versão mais nova do Mural (formato \(future)). Nada foi alterado.")
    }
}

extension BoardRoute {
    fileprivate var id: BoardID? {
        if case .saved(let id) = self { return id }
        return nil
    }
}
