import Foundation
import Testing

@testable import MuralKit

@MainActor
@Suite("Post-it solto na pasta")
struct StickyFolderPlacementTests {
    /// A versão do formato que um post-it num lugar livre da pasta exige.
    private static let requiredVersion = 9

    private let fixture = Fixture()

    /// Uma pasta com dois post-its e uma nota, outra pasta, e um post-it e uma nota soltos no mural.
    /// As datas são explícitas: a ordem dos filhos vem da criação, e dois `Date.now` seguidos podem empatar.
    private struct Fixture {
        let folder: BoardItem
        let first: BoardItem
        let note: BoardItem
        let second: BoardItem
        let looseSticky: BoardItem
        let looseNote: BoardItem
        let other: BoardItem

        init() {
            let folder = BoardItem(kind: .folder, title: "Pasta", createdAt: Self.date(1), position: BoardPoint(x: 40, y: 40))
            self.folder = folder
            first = BoardItem(kind: .sticky, title: "Primeiro", createdAt: Self.date(2), parentID: folder.id, text: "Primeiro")
            note = BoardItem(kind: .text, title: "Nota", createdAt: Self.date(3), parentID: folder.id)
            second = BoardItem(kind: .sticky, title: "Segundo", createdAt: Self.date(4), parentID: folder.id, text: "Segundo")
            looseSticky = BoardItem(
                kind: .sticky, title: "Solto", createdAt: Self.date(5), position: BoardPoint(x: 300, y: 40), text: "Solto")
            looseNote = BoardItem(kind: .text, title: "Nota solta", createdAt: Self.date(6), position: BoardPoint(x: 300, y: 240))
            other = BoardItem(kind: .folder, title: "Outra pasta", createdAt: Self.date(7), position: BoardPoint(x: 560, y: 40))
        }

        static func date(_ seconds: Double) -> Date {
            Date(timeIntervalSince1970: seconds)
        }

        /// Na ordem da lista: o que vem depois fica por cima.
        var items: [BoardItem] { [folder, first, note, second, looseSticky, looseNote, other] }

        var board: Board { Board(items: items) }

        /// O mural como uma build antiga o gravou (versão 0): só uma alteração de fato sobe a versão.
        var olderBoard: Board {
            var board = board
            board.formatVersion = 0
            return board
        }
    }

    private func makeStore() -> BoardStore {
        BoardStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("MuralSticky-\(UUID().uuidString)"))
    }

    private func isNegativeZero(_ value: Double) -> Bool {
        value == 0 && value.sign == .minus
    }

    // MARK: Domínio

    @Test("Pôr no lugar guarda o ponto arredondado, leva o post-it para o fim da lista e não mexe na ordem por data")
    func placesTheRoundedPointAtTheEndOfTheList() {
        let first = fixture.first
        let second = fixture.second
        var board = fixture.board
        let placed = board.placeInFolder(id: first.id, at: BoardPoint(x: -40.4, y: 120.6))
        #expect(placed)

        var expected = first
        expected.folderPosition = BoardPoint(x: -40, y: 121)
        #expect(board.item(id: first.id) == expected, "só o lugar muda: a posição no mural, a pasta e o texto ficam como estavam")
        let expectedOrder = (fixture.items.filter { $0.id != first.id } + [first]).map(\.id)
        #expect(board.items.map(\.id) == expectedOrder)
        #expect(board.placedStickies(in: fixture.folder.id).map(\.id) == [first.id])
        #expect(board.placedStickies(in: fixture.other.id).isEmpty)
        #expect(board.children(of: fixture.folder.id).map(\.id) == [first.id, fixture.note.id, second.id], "os filhos seguem a data")

        // Outro post-it fica por cima do primeiro; pôr o primeiro de novo o leva de volta para cima.
        let secondPlaced = board.placeInFolder(id: second.id, at: BoardPoint(x: 10, y: 20))
        #expect(secondPlaced)
        #expect(board.placedStickies(in: fixture.folder.id).map(\.id) == [first.id, second.id])
        let firstAgain = board.placeInFolder(id: first.id, at: BoardPoint(x: 0, y: 0))
        #expect(firstAgain)
        #expect(board.placedStickies(in: fixture.folder.id).map(\.id) == [second.id, first.id])
        #expect(board.items.last?.id == first.id)
        #expect(board.children(of: fixture.folder.id).map(\.id) == [first.id, fixture.note.id, second.id])
    }

    @Test("O lugar nunca fica acima do topo, e valores inválidos viram 0")
    func clampsTheTopAndInvalidValues() throws {
        let cases: [(name: String, input: BoardPoint, expected: BoardPoint)] = [
            ("y negativo", BoardPoint(x: 30, y: -12.4), BoardPoint(x: 30, y: 0)),
            ("y que arredonda para zero", BoardPoint(x: 30, y: -0.3), BoardPoint(x: 30, y: 0)),
            ("x negativo é válido", BoardPoint(x: -250.5, y: 8), BoardPoint(x: -251, y: 8)),
            ("x que arredonda para zero", BoardPoint(x: -0.3, y: 8), BoardPoint(x: 0, y: 8)),
            ("NaN", BoardPoint(x: .nan, y: .nan), .zero),
            ("infinito", BoardPoint(x: .infinity, y: .infinity), .zero),
            ("menos infinito", BoardPoint(x: -.infinity, y: -.infinity), .zero),
            ("só o x inválido", BoardPoint(x: .nan, y: 25.2), BoardPoint(x: 0, y: 25)),
            ("só o y inválido", BoardPoint(x: 25.2, y: .infinity), BoardPoint(x: 25, y: 0)),
        ]
        for placement in cases {
            var board = fixture.board
            let accepted = board.placeInFolder(id: fixture.first.id, at: placement.input)
            #expect(accepted, "recusou \(placement.name)")
            let stored = try #require(board.item(id: fixture.first.id)?.folderPosition)
            #expect(stored == placement.expected, "\(placement.name)")
            #expect(!isNegativeZero(stored.x) && !isNegativeZero(stored.y), "\(placement.name): o arquivo gravaria -0")
        }
    }

    @Test("Só o post-it de uma pasta aceita o lugar: o resto é recusado sem alterar o mural nem a versão do formato")
    func refusesWhatIsNotAFolderSticky() {
        // Um cartão de cada um dos outros tipos dentro da pasta, a nota entre eles.
        let strangers = ItemKind.allCases.filter { $0 != .sticky }.map {
            BoardItem(kind: $0, title: "Cartão \($0.rawValue)", parentID: fixture.folder.id)
        }
        var older = fixture.olderBoard
        older.items.append(contentsOf: strangers)
        var cases: [(name: String, id: UUID)] = [
            ("post-it solto no mural", fixture.looseSticky.id),
            ("nota dentro da pasta", fixture.note.id),
            ("id desconhecido", UUID()),
        ]
        for stranger in strangers {
            cases.append((name: "cartão \(stranger.kind.rawValue) dentro da pasta", id: stranger.id))
        }
        for refusal in cases {
            var attempt = older
            let accepted = attempt.placeInFolder(id: refusal.id, at: BoardPoint(x: 10, y: 10))
            #expect(!accepted, "aceitou \(refusal.name)")
            #expect(attempt == older, "alterou o mural em \(refusal.name)")
            #expect(attempt.formatVersion == 0, "mexeu na versão em \(refusal.name)")
        }
    }

    @Test("Só o post-it dentro de uma pasta, com lugar, conta como solto na pasta")
    func placedNeedsAStickyInAFolderWithAPlace() {
        let place = BoardPoint(x: 0, y: 40)
        var sticky = fixture.first
        #expect(!sticky.isPlacedInFolder, "sem lugar, o post-it fica nas colunas")
        sticky.folderPosition = place
        #expect(sticky.isPlacedInFolder)

        var loose = fixture.looseSticky
        loose.folderPosition = place
        #expect(!loose.isPlacedInFolder, "solto no mural, o lugar na pasta não vale")

        var note = fixture.note
        note.folderPosition = place
        #expect(!note.isPlacedInFolder, "só o post-it pode ficar solto na pasta")

        let board = Board(items: [fixture.folder, loose, note, sticky])
        #expect(board.placedStickies(in: fixture.folder.id).map(\.id) == [sticky.id])
    }

    @Test("Sair da pasta esquece o lugar livre: outra pasta ou o mural")
    func leavingTheFolderForgetsThePlace() throws {
        let place = BoardPoint(x: -40, y: 121)
        var board = fixture.board
        let firstPlaced = board.placeInFolder(id: fixture.first.id, at: place)
        let secondPlaced = board.placeInFolder(id: fixture.second.id, at: place)
        #expect(firstPlaced && secondPlaced)

        // Para a pasta onde já está não há mudança de pai, e o lugar continua.
        let sameFolder = board.moveIntoFolder(id: fixture.first.id, folderID: fixture.folder.id)
        #expect(!sameFolder)
        #expect(board.item(id: fixture.first.id)?.folderPosition == place)

        let intoOther = board.moveIntoFolder(id: fixture.first.id, folderID: fixture.other.id)
        #expect(intoOther)
        let inOther = try #require(board.item(id: fixture.first.id))
        #expect(inOther.parentID == fixture.other.id)
        #expect(inOther.folderPosition == nil)
        #expect(!inOther.isPlacedInFolder, "na pasta nova, o post-it entra nas colunas")
        #expect(board.placedStickies(in: fixture.other.id).isEmpty)
        #expect(board.placedStickies(in: fixture.folder.id).map(\.id) == [fixture.second.id])

        let toBoard = board.moveToBoard(id: fixture.second.id, at: BoardPoint(x: 90, y: 90))
        #expect(toBoard)
        let loose = try #require(board.item(id: fixture.second.id))
        #expect(loose.parentID == nil)
        #expect(loose.position == BoardPoint(x: 90, y: 90))
        #expect(loose.folderPosition == nil)
        #expect(board.placedStickies(in: fixture.folder.id).isEmpty)
    }

    @Test("O lugar livre exige a versão nova do formato, e o mural volta à versão 1 quando o post-it sai da pasta")
    func formatVersion() {
        #expect(Board.currentFormatVersion >= Self.requiredVersion)
        var board = Board(items: [fixture.folder, fixture.first])
        #expect(board.formatVersion == 1, "controle: sem lugar livre, a pasta com um post-it é da versão 1")

        let placed = board.placeInFolder(id: fixture.first.id, at: BoardPoint(x: 0, y: 40))
        #expect(placed)
        #expect(board.formatVersion == Self.requiredVersion)
        #expect(board.requiredFormatVersion == Self.requiredVersion)
        #expect(Board(items: board.items).formatVersion == Self.requiredVersion, "o inicializador também exige a versão")

        let toBoard = board.moveToBoard(id: fixture.first.id, at: BoardPoint(x: 5, y: 5))
        #expect(toBoard)
        #expect(board.formatVersion == 1, "sem o lugar livre, o mural volta a abrir nas builds anteriores")
        #expect(Board(items: board.items).formatVersion == 1)
    }

    // MARK: Modelo

    @Test("O lugar é gravado: um modelo novo no mesmo armazenamento lê o mesmo ponto")
    func persistsThePlace() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)
        let folder = model.createFolder(named: "Pasta")
        let sticky = model.createSticky(into: folder.id)
        model.createNote(into: folder.id)

        model.placeInFolder(sticky.id, at: BoardPoint(x: -40.4, y: 120.6))
        #expect(model.lastError == nil)
        #expect(model.item(id: sticky.id)?.folderPosition == BoardPoint(x: -40, y: 121))
        #expect(model.board.items.last?.id == sticky.id, "o post-it vai para o fim da lista")
        #expect(model.board.formatVersion == Self.requiredVersion)

        let reopened = BoardModel(store: store, seedIfEmpty: false)
        let reloaded = try #require(reopened.item(id: sticky.id))
        #expect(reloaded.folderPosition == BoardPoint(x: -40, y: 121))
        #expect(reopened.board.placedStickies(in: folder.id).map(\.id) == [sticky.id])
        #expect(reopened.board.formatVersion == Self.requiredVersion)
    }

    @Test("O modelo não grava quando o post-it não pode receber o lugar")
    func refusalDoesNotSave() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)
        let folder = model.createFolder(named: "Pasta")
        let sticky = model.createSticky(into: folder.id)
        let note = model.createNote(into: folder.id)
        let loose = model.createSticky()
        let before = model.board
        // Com uma pasta no lugar do board.json, qualquer gravação falharia e preencheria `lastError`.
        try FileManager.default.removeItem(at: store.fileURL)
        try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: true)

        for id in [note.id, loose.id, UUID()] {
            model.placeInFolder(id, at: BoardPoint(x: 1, y: 1))
        }
        #expect(model.board == before)
        #expect(model.lastError == nil, "nada deveria ter sido gravado")

        model.placeInFolder(sticky.id, at: BoardPoint(x: 1, y: 1))
        #expect(model.lastError != nil, "controle: um lugar válido tenta gravar")
    }

    @Test("Subir o post-it de uma subpasta esquece o lugar, na pasta de cima e no mural")
    func movingUpForgetsThePlace() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)
        let outer = model.createFolder(named: "Externa")
        let inner = try #require(model.createFolder(named: "Interna", into: outer.id))
        let sticky = model.createSticky(into: inner.id)

        model.placeInFolder(sticky.id, at: BoardPoint(x: 30, y: 60))
        #expect(model.item(id: sticky.id)?.folderPosition == BoardPoint(x: 30, y: 60), "controle: o lugar foi guardado")
        model.moveUp(sticky.id)
        let inOuter = try #require(model.item(id: sticky.id))
        #expect(inOuter.parentID == outer.id)
        #expect(inOuter.folderPosition == nil)
        let reopened = try #require(BoardModel(store: store, seedIfEmpty: false).item(id: sticky.id))
        #expect(reopened.parentID == outer.id)
        #expect(reopened.folderPosition == nil)

        model.placeInFolder(sticky.id, at: BoardPoint(x: 70, y: 90))
        #expect(model.item(id: sticky.id)?.folderPosition == BoardPoint(x: 70, y: 90), "controle: o lugar na pasta nova")
        model.moveUp(sticky.id)
        let onBoard = try #require(model.item(id: sticky.id))
        #expect(onBoard.parentID == nil)
        #expect(onBoard.folderPosition == nil)
        #expect(!onBoard.isPlacedInFolder)
        #expect(model.lastError == nil)
    }

    // MARK: JSON

    @Test("No JSON, o lugar só aparece quando existe, e um mural antigo sem a chave abre sem lugar")
    func jsonCarriesThePlaceOnlyWhenItExists() throws {
        let plain = Board(items: [fixture.folder, fixture.first])
        let plainJSON = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        #expect(!plainJSON.contains("folderPosition"), "sem lugar, a chave não é gravada")

        var placed = plain
        placed.placeInFolder(id: fixture.first.id, at: BoardPoint(x: -40, y: 121))
        let placedData = try JSONEncoder().encode(placed)
        #expect(String(decoding: placedData, as: UTF8.self).contains("folderPosition"))
        let decoded = try JSONDecoder().decode(Board.self, from: placedData)
        #expect(decoded == placed)
        #expect(decoded.item(id: fixture.first.id)?.folderPosition == BoardPoint(x: -40, y: 121))

        let legacy = Data(
            """
            {"formatVersion":7,"items":[\
            {"createdAt":0,"id":"5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01","kind":"folder","position":{"x":0,"y":0},"title":"Pasta"},\
            {"createdAt":1,"id":"5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C02","kind":"sticky","parentID":"5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01",\
            "position":{"x":0,"y":0},"text":"Antigo","title":"Antigo"}]}
            """.utf8)
        let old = try JSONDecoder().decode(Board.self, from: legacy)
        let sticky = try #require(old.items.last)
        #expect(sticky.kind == .sticky)
        #expect(sticky.folderPosition == nil)
        #expect(!sticky.isPlacedInFolder)
        #expect(old.formatVersion == 7, "ler não muda a versão do mural")
    }

    // MARK: Pacote portátil

    @Test("O pacote .mural mantém o lugar na ida e volta")
    func packageRoundTripKeepsThePlace() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MuralStickyPackage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = BoardLibrary(rootDirectory: root)
        let route = try await library.createNamedBoard("Original")
        let id = try #require(route.id)
        let repository = try await library.repository(for: route)
        var board = fixture.board
        let placed = board.placeInFolder(id: fixture.first.id, at: BoardPoint(x: -40, y: 121))
        #expect(placed)
        try await repository.save(
            BoardRepositorySnapshot(manifest: BoardManifest(id: id, name: "Original", contentRevision: 1), board: board))

        let exported = try await library.exportPackage(route)
        let imported = try await library.importPackage(from: exported)
        let snapshot = try #require(await library.open(imported))
        #expect(snapshot.board == board)
        #expect(snapshot.board.item(id: fixture.first.id)?.folderPosition == BoardPoint(x: -40, y: 121))
        #expect(snapshot.board.placedStickies(in: fixture.folder.id).map(\.id) == [fixture.first.id])
        #expect(snapshot.board.formatVersion == Self.requiredVersion)
        try await library.cleanupTransfer(exported)
    }

    @Test("O pacote recusa um lugar na pasta que não seja um número finito")
    func packageRefusesAPlaceThatIsNotFinite() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MuralStickyPackage-\(UUID().uuidString)", isDirectory: true)
        let items = root.appendingPathComponent("Items", isDirectory: true)
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = BoardPortablePackageService(availableCapacity: { _ in nil })

        var valid = fixture.first
        valid.folderPosition = BoardPoint(x: -40, y: 121)
        let validBoard = Board(items: [fixture.folder, valid])
        try await service.validateBoard(validBoard, itemsURL: items)

        for invalid in [BoardPoint(x: .infinity, y: 0), BoardPoint(x: 0, y: .nan), BoardPoint(x: -.infinity, y: 5)] {
            var sticky = fixture.first
            sticky.folderPosition = invalid
            let board = Board(items: [fixture.folder, sticky])
            await #expect(throws: BoardPortablePackageError.invalidItemPosition(sticky.id)) {
                try await service.validateBoard(board, itemsURL: items)
            }
        }
    }
}

extension BoardRoute {
    fileprivate var id: BoardID? {
        if case .saved(let id) = self { return id }
        return nil
    }
}
