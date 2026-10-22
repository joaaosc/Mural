import Foundation
import Testing

@testable import MuralKit

@MainActor
@Suite("Cor nos cartões")
struct ColorTagTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MuralColorTag-\(UUID().uuidString)")
    }

    /// Grava um `board.json` escrito à mão, para testar a leitura pelo mesmo caminho do app.
    private func storeWithBoard(json: String) throws -> BoardStore {
        let store = BoardStore(directory: temporaryDirectory())
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: store.fileURL)
        return store
    }

    /// Mural gravado antes de existir o campo `colorTag`.
    private static let legacyBoardJSON = """
        {
          "formatVersion" : 1,
          "items" : [
            {
              "createdAt" : "2026-10-01T12:00:00Z",
              "id" : "5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01",
              "kind" : "folder",
              "position" : { "x" : 420, "y" : 80 },
              "tag" : "CLIENT 001",
              "title" : "The Cottage"
            },
            {
              "createdAt" : "2026-10-01T12:00:01Z",
              "id" : "7C1D5E3F-9D1C-4C2A-8E86-4F2B8A3BAD02",
              "kind" : "sticky",
              "parentID" : "5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01",
              "position" : { "x" : 0, "y" : 0 },
              "stickyColor" : "yellow",
              "text" : "Ideia",
              "title" : "Ideia"
            }
          ]
        }
        """

    @Test("As sete cores, na ordem do menu, são gravadas pelo nome em inglês")
    func colorsAndRawValues() {
        #expect(TagColor.allCases.map(\.rawValue) == ["red", "orange", "yellow", "green", "blue", "purple", "gray"])
        #expect(TagColor.allCases.map(\.id) == TagColor.allCases)
    }

    @Test("Cor definida e removida vale para qualquer tipo de cartão e sobrevive à reabertura")
    func setAndRemovePersists() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = BoardModel(store: BoardStore(directory: directory), seedIfEmpty: false)
        let note = try #require(model.importText("Primeira frase.", as: .text))
        let sticky = model.createSticky()
        let folder = model.createFolder(named: "Obras")
        let cards = [note, sticky, folder]

        for (card, color) in zip(cards, [TagColor.green, .red, .purple]) {
            #expect(model.setColorTag(color, for: card.id))
            #expect(model.item(id: card.id)?.colorTag == color)
        }
        let reopened = BoardModel(store: BoardStore(directory: directory), seedIfEmpty: false)
        #expect(reopened.item(id: note.id)?.colorTag == .green)
        #expect(reopened.item(id: sticky.id)?.colorTag == .red)
        #expect(reopened.item(id: folder.id)?.colorTag == .purple)

        #expect(model.setColorTag(nil, for: note.id))
        #expect(model.item(id: note.id)?.colorTag == nil)
        let reopenedAgain = BoardModel(store: BoardStore(directory: directory), seedIfEmpty: false)
        #expect(reopenedAgain.item(id: note.id)?.colorTag == nil)
        #expect(reopenedAgain.item(id: sticky.id)?.colorTag == .red, "a cor dos outros cartões não muda")
    }

    @Test("A mesma cor de novo devolve false e não mexe no mural nem na versão")
    func sameColorIsANoOp() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = BoardModel(store: BoardStore(directory: directory), seedIfEmpty: false)
        let note = try #require(model.importText("Uma nota", as: .text))

        #expect(model.setColorTag(.blue, for: note.id))
        #expect(model.board.formatVersion == 4)

        model.board.formatVersion = 0
        let before = model.board
        #expect(!model.setColorTag(.blue, for: note.id))
        #expect(model.board == before)
        #expect(model.board.formatVersion == 0, "a mesma cor de novo não é uma alteração")

        #expect(!model.setColorTag(.blue, for: UUID()), "cartão que não existe")
        #expect(!model.setColorTag(nil, for: UUID()), "cartão que não existe, sem cor")
        let plain = model.createSticky()
        #expect(!model.setColorTag(nil, for: plain.id), "tirar a cor de quem não tem não é uma alteração")
    }

    @Test("Mural gravado antes da cor abre com todos os cartões sem cor")
    func legacyBoardOpensWithoutColor() throws {
        let store = try storeWithBoard(json: Self.legacyBoardJSON)
        defer { try? FileManager.default.removeItem(at: store.directory) }

        let board = try #require(try store.load())
        #expect(board.items.map(\.kind) == [.folder, .sticky])
        #expect(board.items.allSatisfy { $0.colorTag == nil })
        #expect(board.items.first { $0.kind == .sticky }?.text == "Ideia")
        #expect(board.formatVersion == 1)
    }

    @Test("Cartão sem cor é gravado sem a chave nova, e com cor a chave leva o nome da cor")
    func colorKeyIsWrittenOnlyWhenSet() throws {
        let store = BoardStore(directory: temporaryDirectory())
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let plain = BoardItem(kind: .sticky, title: "Nota", text: "x")
        try store.save(Board(items: [BoardItem(kind: .folder, title: "Pasta"), plain]))
        let withoutColor = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(!withoutColor.contains("colorTag"))

        var colored = plain
        colored.colorTag = .orange
        try store.save(Board(items: [colored]))
        let withColor = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(withColor.contains("\"colorTag\" : \"orange\""))
        #expect(try store.load()?.items.first?.colorTag == .orange)
    }

    @Test("Mural com alguma cor exige a versão 4; sem a última cor, volta a abrir nas versões anteriores")
    func requiredVersionFollowsColor() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = BoardModel(store: BoardStore(directory: directory), seedIfEmpty: false)
        let first = try #require(model.importText("Primeira", as: .text))
        let second = model.createSticky()
        #expect(model.board.requiredFormatVersion <= 2)
        #expect(model.board.formatVersion <= 2)

        #expect(model.setColorTag(.red, for: first.id))
        #expect(model.board.requiredFormatVersion == 4)
        #expect(model.board.formatVersion == 4)
        #expect(Board(items: model.board.items).formatVersion == 4)

        #expect(model.setColorTag(.gray, for: second.id))
        #expect(model.setColorTag(nil, for: first.id))
        #expect(model.board.requiredFormatVersion == 4, "ainda há um cartão com cor")
        #expect(model.board.formatVersion == 4)

        #expect(model.setColorTag(nil, for: second.id))
        #expect(model.board.requiredFormatVersion <= 2)
        #expect(model.board.formatVersion <= 2, "sem cor, o mural não tranca as builds anteriores")
        let reopened = BoardModel(store: BoardStore(directory: directory), seedIfEmpty: false)
        #expect(reopened.board.formatVersion <= 2)
    }

    @Test("Com um cartão de link no mural, tirar a última cor volta à versão 3, não à anterior")
    func removingColorKeepsLinkVersion() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = BoardModel(store: BoardStore(directory: directory), seedIfEmpty: false)
        let address = try #require(URL(string: "https://www.apple.com/mac"))
        let link = try #require(model.importLinks([LinkDraft(url: address)]).first)
        #expect(model.board.formatVersion == 3, "controle: o link sozinho exige a versão 3")

        #expect(model.setColorTag(.purple, for: link.id))
        #expect(model.board.formatVersion == 4)

        #expect(model.setColorTag(nil, for: link.id))
        #expect(model.board.requiredFormatVersion == 3)
        #expect(model.board.formatVersion == 3, "o link continua exigindo a versão 3")
    }
}
