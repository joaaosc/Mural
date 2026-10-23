import Foundation
import Testing

@testable import MuralKit

@MainActor
@Suite("Cartão de música")
struct MusicCardTests {
    private func makeStore() -> BoardStore {
        BoardStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("MuralMusic-\(UUID().uuidString)"))
    }

    private func snapshot(_ id: String = "1", title: String = "Abbey Road", artwork: String? = nil) -> MusicSnapshot {
        MusicSnapshot(
            kind: .album, catalogID: id, url: URL(string: "https://music.apple.com/br/album/\(id)"), title: title,
            subtitle: "The Beatles", artworkFile: artwork, backgroundHex: "#112233", trackCount: 17)
    }

    private func assertPackageError(_ board: Board, _ expected: BoardPortablePackageError) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MuralMusicPkg-\(UUID().uuidString)")
        let items = root.appendingPathComponent("Items", isDirectory: true)
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = BoardPortablePackageService(availableCapacity: { _ in nil })
        do {
            try await service.validateBoard(board, itemsURL: items)
            Issue.record("esperado \(expected), a validação passou")
        } catch {
            #expect((error as? BoardPortablePackageError) == expected)
        }
    }

    @Test("A versão 8 só aparece com cartão de música")
    func formatVersion() {
        #expect(Board.currentFormatVersion >= 8)
        #expect(Board(items: [BoardItem(kind: .sticky, title: "")]).requiredFormatVersion == 1)
        #expect(Board(items: [BoardItem(kind: .reminder, title: "x", reminder: ReminderSnapshot(identifier: "R", title: "x"))]).requiredFormatVersion == 6)
        #expect(Board(items: [BoardItem(kind: .music, title: "x", music: snapshot())]).requiredFormatVersion == 8)
        #expect(!ItemKind.music.storesFile)
    }

    @Test("Ida e volta em JSON, e mural antigo sem o campo abre")
    func jsonRoundTrip() throws {
        let item = BoardItem(kind: .music, title: "Abbey Road", music: snapshot())
        let decodedItem = try JSONDecoder().decode(BoardItem.self, from: JSONEncoder().encode(item))
        #expect(decodedItem == item)
        #expect(decodedItem.music == snapshot())

        let board = Board(items: [item])
        #expect(try JSONDecoder().decode(Board.self, from: JSONEncoder().encode(board)) == board)

        let legacy = Data(
            """
            {"formatVersion":5,"items":[{"createdAt":0,"id":"5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01","kind":"sticky","position":{"x":0,"y":0},"title":""}]}
            """.utf8)
        #expect(try JSONDecoder().decode(Board.self, from: legacy).items.first?.music == nil)
    }

    @Test("importMusic cria um cartão por item, sem repetir no lote, e grava uma vez")
    func importCreatesCards() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)
        let created = model.importMusic([snapshot("A"), snapshot("B", title: "Let It Be"), snapshot("A")])
        #expect(created.count == 2)
        #expect(created.map(\.title) == ["Abbey Road", "Let It Be"])
        #expect(created.allSatisfy { $0.kind == .music && $0.fileName == nil && $0.parentID == nil })
        #expect(created[0].createdAt < created[1].createdAt)
        let size = BoardLayout.cardSize(for: .music)
        #expect(size.width == 150 && size.height == 196)
        #expect(!BoardLayout.overlaps(created[0].position, size, created[1].position, size, gap: 0))
        #expect(model.musicItems.count == 2)

        let folder = model.createFolder(named: "Discos")
        let inside = model.importMusic([snapshot("A")], into: folder.id)
        #expect(inside.first?.parentID == folder.id)
        #expect(model.musicItems.count == 3)
        #expect(BoardModel(store: BoardStore(directory: store.directory), seedIfEmpty: false).musicItems.count == 3)
    }

    @Test("Lote vazio não grava nada")
    func emptyBatchDoesNotPersist() {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)
        // Com uma pasta no lugar do board.json, qualquer gravação falharia e preencheria `lastError`.
        try? FileManager.default.removeItem(at: store.fileURL)
        try? FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: true)
        #expect(model.importMusic([]).isEmpty)
        #expect(model.lastError == nil)
        #expect(model.importMusic([snapshot()]).count == 1)
        #expect(model.lastError != nil, "controle: um cartão novo tenta gravar")
    }

    @Test("updateMusic só grava quando muda, e o título acompanha")
    func updatesOnlyWhenChanged() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)
        let item = try #require(model.importMusic([snapshot()]).first)
        #expect(model.updateMusic(item.id, with: snapshot()) == false)
        var changed = snapshot(title: "Abbey Road (Remaster)")
        changed.trackCount = 18
        #expect(model.updateMusic(item.id, with: changed))
        #expect(model.item(id: item.id)?.title == "Abbey Road (Remaster)")
        #expect(model.item(id: item.id)?.music?.trackCount == 18)
        #expect(model.updateMusic(item.id, with: changed) == false)
        let note = model.createNote()
        #expect(model.updateMusic(note.id, with: changed) == false)
    }

    @Test("referencedLinkPreviewFiles inclui a capa das músicas")
    func referencedFilesIncludeArtwork() {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)
        #expect(model.referencedLinkPreviewFiles.isEmpty)
        let folder = model.createFolder(named: "Discos")
        model.importMusic([snapshot("A", artwork: "capa-a.jpg"), snapshot("B")])
        model.importMusic([snapshot("C", artwork: "capa-c.jpg")], into: folder.id)
        #expect(model.referencedLinkPreviewFiles == ["capa-a.jpg", "capa-c.jpg"])
    }

    @Test("A validação do pacote exige o estado da música, sem arquivo e com nome de capa seguro")
    func packageValidation() async throws {
        let id = UUID()
        let service = BoardPortablePackageService(availableCapacity: { _ in nil })
        let items = FileManager.default.temporaryDirectory.appendingPathComponent("MuralMusicOK-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: items) }
        let valid = BoardItem(id: id, kind: .music, title: "x", music: snapshot(artwork: "capa.jpg"))
        try await service.validateBoard(Board(items: [valid]), itemsURL: items)

        try await assertPackageError(Board(items: [BoardItem(id: id, kind: .music, title: "x")]), .invalidMusic(id))
        try await assertPackageError(
            Board(items: [BoardItem(id: id, kind: .music, title: "x", fileName: "a.png", music: snapshot())]), .invalidMusic(id))
        try await assertPackageError(
            Board(items: [BoardItem(id: id, kind: .sticky, title: "x", music: snapshot())]), .invalidMusic(id))
        try await assertPackageError(
            Board(items: [BoardItem(id: id, kind: .music, title: "x", music: snapshot(artwork: "../capa.jpg"))]), .invalidMusic(id))
        var longTitle = snapshot()
        longTitle.title = String(repeating: "a", count: 1_001)
        try await assertPackageError(Board(items: [BoardItem(id: id, kind: .music, title: "x", music: longTitle)]), .invalidMusic(id))
        var longSubtitle = snapshot()
        longSubtitle.subtitle = String(repeating: "a", count: 1_001)
        try await assertPackageError(Board(items: [BoardItem(id: id, kind: .music, title: "x", music: longSubtitle)]), .invalidMusic(id))
        var longPlaylist = snapshot()
        longPlaylist.libraryPlaylistName = String(repeating: "a", count: 1_001)
        try await assertPackageError(Board(items: [BoardItem(id: id, kind: .music, title: "x", music: longPlaylist)]), .invalidMusic(id))
        try await assertPackageError(
            Board(items: [BoardItem(id: id, kind: .music, title: String(repeating: "a", count: 1_001), music: snapshot())]), .invalidMusic(id))
    }
}
