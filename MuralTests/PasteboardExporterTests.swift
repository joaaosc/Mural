import AppKit
import MuralKit
import Testing

@testable import Mural

/// Todos os testes usam uma área de transferência privada: a geral é do usuário e nunca é tocada.
@MainActor
struct PasteboardExporterTests {
    private static let urlName = NSPasteboard.PasteboardType("public.url-name")

    @Test("Copiar um link grava o endereço, o título do cartão e o endereço como texto")
    func linkWritesURLTitleAndString() throws {
        let pasteboard = Self.makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let url = try #require(URL(string: "https://www.apple.com/br/mac/?ref=mural"))
        let item = BoardItem(kind: .link, title: "Mac – Apple (BR)", link: LinkInfo(url: url, pageTitle: "Outro título"))

        PasteboardExporter.copy(item, from: Self.makeModel(), to: pasteboard)

        #expect(pasteboard.pasteboardItems?.count == 1)
        #expect(pasteboard.string(forType: .URL) == "https://www.apple.com/br/mac/?ref=mural")
        #expect(pasteboard.string(forType: Self.urlName) == "Mac – Apple (BR)")
        #expect(pasteboard.string(forType: .string) == "https://www.apple.com/br/mac/?ref=mural")
        // Quem cola lê um endereço de verdade, não só texto.
        #expect(pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] == [url])
    }

    @Test("Copiar uma nota continua gravando o texto, sem sobras do que estava na área antes")
    func noteWritesTextAndClearsPreviousContents() throws {
        let pasteboard = Self.makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let model = Self.makeModel()
        let url = try #require(URL(string: "https://apple.com"))
        PasteboardExporter.copy(BoardItem(kind: .link, title: "Apple", link: LinkInfo(url: url)), from: model, to: pasteboard)

        PasteboardExporter.copy(BoardItem(kind: .text, title: "Ideias", text: "Corpo da nota"), from: model, to: pasteboard)

        #expect(pasteboard.string(forType: .string) == "# Ideias\n\nCorpo da nota")
        #expect(pasteboard.string(forType: .URL) == nil)
        #expect(pasteboard.string(forType: Self.urlName) == nil)
    }

    @Test("Sem corpo, a nota grava o título")
    func noteWithoutBodyWritesTitle() {
        let pasteboard = Self.makePasteboard()
        defer { pasteboard.releaseGlobally() }

        PasteboardExporter.copy(BoardItem(kind: .sticky, title: "Lembrete"), from: Self.makeModel(), to: pasteboard)

        #expect(pasteboard.string(forType: .string) == "Lembrete")
    }

    @Test("Copiar uma lista grava o texto no formato que o mural reconhece ao colar")
    func checklistWritesParserFormat() {
        let pasteboard = Self.makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let document = SampleBoard.thingsINeed
        let item = BoardItem(kind: .checklist, title: document.title, checklist: document)

        PasteboardExporter.copy(item, from: Self.makeModel(), to: pasteboard)

        #expect(pasteboard.string(forType: .string) == ChecklistParser.format(document))
    }

    @Test("Copiar um cartão com arquivo grava o endereço do arquivo")
    func storedFileWritesFileURL() throws {
        let pasteboard = Self.makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let store = Self.makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try FileManager.default.createDirectory(at: store.itemsDirectory, withIntermediateDirectories: true)
        try Data("png".utf8).write(to: store.itemsDirectory.appendingPathComponent("foto.png"))
        let model = BoardModel(board: Board(), store: store, persistence: .deferred)

        PasteboardExporter.copy(BoardItem(kind: .image, title: "Foto", fileName: "foto.png"), from: model, to: pasteboard)

        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        #expect(urls?.map(\.lastPathComponent) == ["foto.png"])
    }

    // MARK: Apoio

    private static func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("MuralTests-\(UUID().uuidString)"))
    }

    private static func makeStore() -> BoardStore {
        BoardStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                "MuralTests-Pasteboard-\(UUID().uuidString)", isDirectory: true))
    }

    /// Mural vazio com gravação adiada: nada vai para o disco.
    private static func makeModel() -> BoardModel {
        BoardModel(board: Board(), store: makeStore(), persistence: .deferred)
    }
}
