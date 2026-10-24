import Foundation
import Testing

@testable import MuralKit

@MainActor
@Suite("Links no mural")
struct BoardModelLinkTests {
    private func makeStore() -> BoardStore {
        BoardStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("MuralModelLinks-\(UUID().uuidString)"))
    }

    private func draft(_ text: String, title: String? = nil, summary: String? = nil, imageURL: String? = nil) throws -> LinkDraft {
        LinkDraft(
            url: try #require(URL(string: text)), title: title, summary: summary,
            imageURL: try imageURL.map { try #require(URL(string: $0)) })
    }

    private func drafts(_ count: Int) throws -> [LinkDraft] {
        try (1...count).map { try draft("https://example.com/pagina-\($0)") }
    }

    private var linkSize: (width: Double, height: Double) { BoardLayout.cardSize(for: .link) }

    // MARK: Posição

    @Test("Links soltos sem ponto ocupam vagas livres e não cobrem nenhum cartão")
    func looseLinksDoNotOverlap() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store)

        let created = model.importLinks(try drafts(4))

        #expect(created.count == 4)
        for link in created {
            #expect(link.parentID == nil)
            for other in model.rootItems where other.id != link.id {
                let otherSize = BoardLayout.cardSize(for: other.kind)
                #expect(
                    !BoardLayout.overlaps(link.position, linkSize, other.position, otherSize, gap: 0),
                    "\(link.title) cobre \(other.title)")
            }
        }
    }

    @Test("Dentro de uma pasta o link recebe a pasta e não entra no mural")
    func linksInsideFolderKeepTheParent() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store)
        let folder = try #require(model.rootItems.first { $0.kind == .folder })
        let rootBefore = model.rootItems.map(\.id)
        let childrenBefore = model.children(of: folder.id).count

        let created = model.importLinks(try drafts(2), into: folder.id)

        #expect(created.count == 2)
        #expect(created.allSatisfy { $0.parentID == folder.id })
        #expect(model.rootItems.map(\.id) == rootBefore)
        #expect(model.children(of: folder.id).count == childrenBefore + 2)
    }

    // MARK: Filtro e lote

    @Test("Endereços que não são da web são ignorados e os válidos entram")
    func invalidDraftsAreIgnored() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)

        let created = model.importLinks([
            try draft("ftp://apple.com/arquivo"), try draft("https://apple.com/mac"), try draft("mailto:someone@example.com"),
            try draft("file:///Users/test-user/nota.txt"), try draft("https://"), try draft("javascript:alert(1)"),
        ])

        #expect(created.map { $0.link?.url.absoluteString } == ["https://apple.com/mac"])
        #expect(model.board.items.count == 1)
    }

    @Test("Lote sem nenhum endereço válido não altera nem grava o mural")
    func batchWithoutValidDraftsDoesNotPersist() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store)
        let boardBefore = model.board

        // Com uma pasta no lugar do board.json, qualquer gravação falharia e preencheria `lastError`.
        try FileManager.default.removeItem(at: store.fileURL)
        try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: true)

        #expect(model.importLinks([]).isEmpty)
        #expect(model.importLinks([try draft("ftp://apple.com"), try draft("mailto:someone@example.com")]).isEmpty)
        #expect(model.board == boardBefore)
        #expect(model.lastError == nil)

        model.importLinks(try drafts(1))
        #expect(model.lastError != nil, "controle: um link válido tenta gravar")
    }

    @Test("Repetidos no lote viram um só, mas o mesmo link pode entrar de novo depois e em outra pasta")
    func duplicatesAreRemovedOnlyWithinTheBatch() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store)
        let folder = try #require(model.rootItems.first { $0.kind == .folder })
        let linksBefore = model.board.items.count { $0.kind == .link }

        let created = model.importLinks([
            try draft("http://www.example.com/a/", title: "Primeiro"),
            try draft("https://example.com/a?utm_source=news#fim", title: "Repetido"),
            try draft("https://example.com/b"),
        ])
        #expect(created.map(\.title) == ["Primeiro", "example.com"])
        #expect(created.first?.link?.url.absoluteString == "http://www.example.com/a/", "vale a primeira ocorrência")

        let again = model.importLinks([try draft("https://example.com/a")])
        let inFolder = model.importLinks([try draft("https://example.com/a")], into: folder.id)
        #expect(again.count == 1 && inFolder.count == 1)
        #expect(model.board.items.count { $0.kind == .link } == linksBefore + 4)
    }

    // MARK: Cartão criado

    @Test("O título é o do rascunho sem espaços nas pontas ou, sem ele, o host")
    func titleFallsBackToHost() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)

        let created = model.importLinks([
            try draft("https://www.apple.com/mac", title: "  Apple Mac \n"),
            try draft("https://www.apple.com/iphone", title: nil),
            try draft("https://www.apple.com/ipad", title: " \n "),
            try draft("https://support.apple.com/pt-br", title: ""),
        ])

        #expect(created.map(\.title) == ["Apple Mac", "apple.com", "apple.com", "support.apple.com"])
    }

    @Test("Só com o endereço, o cartão nasce com a prévia pendente e vazia e sem arquivo guardado")
    func createdItemShape() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)

        let created = model.importLinks([try draft("https://apple.com"), try draft("https://swift.org")])

        #expect(created.map { $0.link?.url.absoluteString } == ["https://apple.com", "https://swift.org"])
        for item in created {
            #expect(item.kind == .link)
            #expect(item.link?.preview == .pending)
            #expect(item.link?.pageTitle == nil && item.link?.siteName == nil && item.link?.summary == nil)
            #expect(item.link?.remoteImageURL == nil && item.link?.previewImageFile == nil && item.link?.iconFile == nil)
            #expect(item.fileName == nil && model.fileURL(for: item) == nil)
        }
    }

    @Test("Resumo e imagem que vieram com o rascunho passam para a prévia do cartão")
    func summaryAndImageComeFromTheDraft() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)

        let created = model.importLinks([
            try draft("https://apple.com/mac", summary: "  O Mac mais rápido de todos.\n", imageURL: "https://cdn.example.com/capa.jpg"),
            try draft("https://swift.org", imageURL: "http://cdn.example.com/swift.png"),
            try draft("https://example.com", summary: "Só o resumo"),
            try draft("https://example.org"),
        ])

        #expect(created.map { $0.link?.summary } == ["O Mac mais rápido de todos.", nil, "Só o resumo", nil])
        #expect(
            created.map { $0.link?.remoteImageURL?.absoluteString }
                == ["https://cdn.example.com/capa.jpg", "http://cdn.example.com/swift.png", nil, nil])
        // O resto da prévia continua por buscar.
        for item in created {
            #expect(item.link?.preview == .pending)
            #expect(item.link?.pageTitle == nil && item.link?.siteName == nil)
            #expect(item.link?.previewImageFile == nil && item.link?.iconFile == nil)
        }
    }

    @Test("Resumo vazio ou só com espaços e quebras não vira texto de prévia", arguments: ["", "   ", " \n\t ", "\u{00A0}"])
    func blankSummaryIsDropped(summary: String) throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)

        let created = model.importLinks([try draft("https://apple.com", summary: summary)])

        #expect(created.count == 1)
        #expect(created.first?.link?.summary == nil)
    }

    @Test(
        "Imagem que não é http nem https é descartada, e o cartão nasce mesmo assim",
        arguments: [
            "data:image/png;base64,iVBORw0KGgo=", "file:///Users/test-user/capa.png", "ftp://cdn.example.com/capa.png",
            "javascript:alert(1)", "/capa.png", "https://",
        ])
    func nonWebImageIsDropped(image: String) throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)

        let created = model.importLinks([try draft("https://apple.com", summary: "Resumo", imageURL: image)])

        #expect(created.count == 1)
        #expect(created.first?.link?.remoteImageURL == nil)
        #expect(created.first?.link?.summary == "Resumo")
    }

    @Test("createdAt cresce 1 ms por link e a pasta mostra os links na ordem do lote")
    func createdAtFollowsBatchOrder() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store)
        let folder = try #require(model.rootItems.first { $0.kind == .folder })
        let before = Date.now

        let created = model.importLinks(try drafts(5), into: folder.id)

        let dates = created.map(\.createdAt)
        #expect(dates.first.map { $0 >= before && $0.timeIntervalSince(before) < 60 } == true)
        for (earlier, later) in zip(dates, dates.dropFirst()) {
            #expect(abs(later.timeIntervalSince(earlier) - 0.001) < 0.0001)
        }
        // O mural de exemplo já tem cartões na pasta, alguns com data futura: só os links contam aqui.
        #expect(model.children(of: folder.id).filter { $0.kind == .link }.map(\.id) == created.map(\.id))
    }

    // MARK: Gravação

    @Test("A ordem do lote na pasta sobrevive ao reabrir, mesmo com as datas gravadas em segundos inteiros")
    func batchOrderSurvivesReopen() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store)
        let folder = try #require(model.rootItems.first { $0.kind == .folder })

        // Os 80 links nascem com poucos milissegundos de diferença: depois de gravados, quase todos empatam em `createdAt`.
        let created = model.importLinks(try drafts(80), into: folder.id)

        let reopened = BoardModel(store: store)
        #expect(reopened.children(of: folder.id).filter { $0.kind == .link }.map(\.id) == created.map(\.id))
    }

    @Test("Links gravados reaparecem iguais ao reabrir o mural")
    func linksPersist() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store)
        let folder = try #require(model.rootItems.first { $0.kind == .folder })

        let loose = model.importLinks(
            [try draft("https://apple.com", title: "Apple", summary: "Descrição", imageURL: "https://cdn.example.com/capa.jpg")])
        let inside = model.importLinks([try draft("https://swift.org"), try draft("https://example.com")], into: folder.id)
        #expect(model.lastError == nil)
        #expect(loose.first?.link?.summary == "Descrição" && loose.first?.link?.remoteImageURL != nil, "controle: o rascunho trouxe prévia")

        let reopened = BoardModel(store: store)
        #expect(reopened.board.items.map(\.id) == model.board.items.map(\.id))
        for item in loose + inside {
            let saved = try #require(reopened.item(id: item.id))
            #expect(saved.kind == .link)
            #expect(saved.title == item.title)
            #expect(saved.parentID == item.parentID)
            #expect(saved.position == item.position)
            #expect(saved.link == item.link)
            // O arquivo guarda datas em segundos inteiros.
            #expect(abs(saved.createdAt.timeIntervalSince(item.createdAt)) < 1)
        }
    }

    @Test("Com gravação adiada o modelo guarda os links na memória e deixa o disco para a sessão")
    func deferredPersistenceDoesNotWrite() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(board: Board(), store: store, persistence: .deferred)

        let created = model.importLinks(try drafts(2))

        #expect(model.board.items.map(\.id) == created.map(\.id))
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }
}
