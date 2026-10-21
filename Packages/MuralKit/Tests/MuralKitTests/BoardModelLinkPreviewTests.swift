import Foundation
import Testing

@testable import MuralKit

@MainActor
@Suite("Prévias de links no mural")
struct BoardModelLinkPreviewTests {
    /// Em segundos inteiros, porque o `BoardStore` grava datas em ISO-8601 sem frações.
    private static let noon = Date(timeIntervalSince1970: 1_792_497_600)

    private func makeStore() -> BoardStore {
        BoardStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("MuralModelPreviews-\(UUID().uuidString)"))
    }

    private func url(_ text: String) throws -> URL {
        try #require(URL(string: text))
    }

    /// Cria um cartão de link pelo caminho normal de importação.
    private func addLink(
        _ model: BoardModel, _ address: String = "https://www.apple.com/mac", title: String? = nil, summary: String? = nil,
        image: String? = nil
    ) throws -> BoardItem {
        let draft = LinkDraft(url: try url(address), title: title, summary: summary, imageURL: try image.map { try url($0) })
        return try #require(model.importLinks([draft]).first)
    }

    private func link(_ model: BoardModel, _ id: UUID) throws -> LinkInfo {
        try #require(model.item(id: id)?.link)
    }

    /// Muda os dados de link de um cartão direto no mural, para montar o estado de partida do teste.
    private func setLink(_ model: BoardModel, _ id: UUID, _ change: (inout LinkInfo) -> Void) throws {
        let index = try #require(model.board.items.firstIndex { $0.id == id })
        var info = try #require(model.board.items[index].link)
        change(&info)
        model.board.items[index].link = info
    }

    private func ready(
        _ id: UUID, title: String? = nil, site: String? = nil, summary: String? = nil, image: String? = nil, imageFile: String? = nil,
        iconFile: String? = nil, at date: Date = noon
    ) -> LinkPreviewUpdate {
        LinkPreviewUpdate(
            itemID: id, pageTitle: title, siteName: site, summary: summary, remoteImageURL: image.flatMap { URL(string: $0) },
            previewImageFile: imageFile, iconFile: iconFile, state: .ready(fetchedAt: date))
    }

    // MARK: Sucesso

    @Test("Busca bem-sucedida preenche o cartão e troca o título provisório pelo título da página, aparado")
    func readyFillsTheCard() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)
        let card = try addLink(model)
        #expect(card.title == "apple.com", "controle: o título nasce provisório")

        model.applyLinkPreviews([
            ready(
                card.id, title: "  Apple Mac \n", site: " Apple ", summary: " Descrição da página ", image: "https://cdn.apple.com/mac.jpg",
                imageFile: "capa.jpg", iconFile: "icone.png")
        ])

        let saved = try #require(model.item(id: card.id))
        #expect(saved.title == "Apple Mac")
        let info = try #require(saved.link)
        #expect(info.url == card.link?.url)
        #expect(info.pageTitle == "Apple Mac" && info.siteName == "Apple" && info.summary == "Descrição da página")
        #expect(info.remoteImageURL?.absoluteString == "https://cdn.apple.com/mac.jpg")
        #expect(info.previewImageFile == "capa.jpg" && info.iconFile == "icone.png")
        #expect(info.preview == .ready(fetchedAt: Self.noon))
        #expect(saved.position == card.position && saved.parentID == card.parentID && saved.createdAt == card.createdAt)
    }

    @Test("O título dado ao importar (o do Safari) não é trocado, mas o título da página fica guardado")
    func givenTitleIsKept() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)
        let card = try addLink(model, title: "Título do Safari")

        model.applyLinkPreviews([ready(card.id, title: "Título da página")])

        #expect(model.item(id: card.id)?.title == "Título do Safari")
        #expect(try link(model, card.id).pageTitle == "Título da página")
    }

    @Test("Um cartão renomeado, mesmo para o host de outro endereço, não tem o título trocado")
    func renamedCardKeepsItsTitle() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)
        let card = try addLink(model)
        let index = try #require(model.board.items.firstIndex { $0.id == card.id })
        model.board.items[index].title = "Meu nome para este link"
        let other = try addLink(model, "https://swift.org/blog")
        let otherIndex = try #require(model.board.items.firstIndex { $0.id == other.id })
        model.board.items[otherIndex].title = "apple.com"

        model.applyLinkPreviews([ready(card.id, title: "Título da página"), ready(other.id, title: "Swift Blog")])

        #expect(model.item(id: card.id)?.title == "Meu nome para este link")
        #expect(model.item(id: other.id)?.title == "apple.com", "só vale o host do próprio endereço do cartão")
    }

    @Test("Título da página vazio ou em branco não vira título do cartão nem apaga o que já existe")
    func blankPageTitleChangesNothing() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)
        let card = try addLink(model)

        model.applyLinkPreviews([ready(card.id, title: " \n\t ", site: "")])
        #expect(model.item(id: card.id)?.title == "apple.com")
        #expect(try link(model, card.id).pageTitle == nil && link(model, card.id).siteName == nil)
        #expect(try link(model, card.id).preview == .ready(fetchedAt: Self.noon))

        model.applyLinkPreviews([ready(card.id, title: "Apple", site: "Apple Inc.")])
        model.applyLinkPreviews([ready(card.id, title: nil, site: "  ", at: Self.noon.addingTimeInterval(60))])
        let info = try link(model, card.id)
        #expect(info.pageTitle == "Apple" && info.siteName == "Apple Inc.", "vazio nunca apaga")
        #expect(info.preview == .ready(fetchedAt: Self.noon.addingTimeInterval(60)))

        model.applyLinkPreviews([ready(card.id, title: "Apple Mac", site: "Apple")])
        #expect(try link(model, card.id).pageTitle == "Apple Mac" && link(model, card.id).siteName == "Apple", "valor novo substitui")
    }

    @Test("O resumo e a imagem que vieram do Safari ao arrastar têm prioridade sobre os da página")
    func safariSummaryAndImageArePreserved() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)
        let withBoth = try addLink(model, "https://apple.com/mac", summary: "Resumo do Safari", image: "https://safari.example/capa.jpg")
        let withNeither = try addLink(model, "https://swift.org")

        model.applyLinkPreviews([
            ready(withBoth.id, summary: "Resumo da página", image: "https://pagina.example/og.jpg", imageFile: "a.jpg"),
            ready(withNeither.id, summary: "Resumo da página", image: "https://pagina.example/og.jpg", imageFile: "b.jpg"),
        ])

        let kept = try link(model, withBoth.id)
        #expect(kept.summary == "Resumo do Safari" && kept.remoteImageURL?.absoluteString == "https://safari.example/capa.jpg")
        #expect(kept.previewImageFile == "a.jpg", "a cópia local da imagem entra mesmo assim")
        let filled = try link(model, withNeither.id)
        #expect(filled.summary == "Resumo da página" && filled.remoteImageURL?.absoluteString == "https://pagina.example/og.jpg")
    }

    @Test("Resumo em branco no cartão conta como ausente, e imagem remota que não é da web é ignorada")
    func blankSummaryIsFilledAndNonWebImageIsIgnored() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)
        let card = try addLink(model)
        try setLink(model, card.id) { $0.summary = "  \n" }

        model.applyLinkPreviews([ready(card.id, summary: "  Resumo novo  ", image: "ftp://cdn.example.com/capa.png")])

        let info = try link(model, card.id)
        #expect(info.summary == "Resumo novo")
        #expect(info.remoteImageURL == nil)

        // Resumo em branco vindo da busca não preenche nada.
        let other = try addLink(model, "https://swift.org")
        model.applyLinkPreviews([ready(other.id, summary: "   ")])
        #expect(try link(model, other.id).summary == nil)
    }

    @Test("Arquivo nulo não apaga o antigo; arquivo novo substitui")
    func nilFileDoesNotEraseTheOldOne() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)
        let card = try addLink(model)
        model.applyLinkPreviews([ready(card.id, imageFile: "capa-1.jpg", iconFile: "icone-1.png")])

        model.applyLinkPreviews([ready(card.id, title: "Sem arquivos", imageFile: nil, iconFile: nil)])
        #expect(try link(model, card.id).previewImageFile == "capa-1.jpg" && link(model, card.id).iconFile == "icone-1.png")

        model.applyLinkPreviews([ready(card.id, imageFile: "capa-2.jpg", iconFile: nil)])
        #expect(try link(model, card.id).previewImageFile == "capa-2.jpg" && link(model, card.id).iconFile == "icone-1.png")

        model.applyLinkPreviews([ready(card.id, imageFile: nil, iconFile: "icone-2.png")])
        #expect(try link(model, card.id).previewImageFile == "capa-2.jpg" && link(model, card.id).iconFile == "icone-2.png")
    }

    // MARK: Falha

    @Test("Falha mantém tudo, mesmo os campos que o resultado traga, e só troca o estado")
    func failureKeepsEverythingButTheState() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)
        let card = try addLink(model, summary: "Resumo do Safari")
        model.applyLinkPreviews([
            ready(card.id, title: "Apple", site: "Apple", summary: "outro", imageFile: "capa.jpg", iconFile: "icone.png")
        ])
        let before = try #require(model.item(id: card.id))

        let failure = LinkPreviewUpdate(
            itemID: card.id, pageTitle: "Não deve entrar", siteName: "Nem este", summary: "Nem este",
            remoteImageURL: try url("https://x.example/i.png"),
            previewImageFile: "nova.jpg", iconFile: "nova.png", state: .failed(at: Self.noon.addingTimeInterval(3_600), attempts: 2))
        model.applyLinkPreviews([failure])

        var expected = before
        expected.link?.preview = .failed(at: Self.noon.addingTimeInterval(3_600), attempts: 2)
        #expect(model.item(id: card.id) == expected)
        #expect(model.item(id: card.id)?.title == "Apple")
    }

    @Test("Falha num cartão pendente deixa os campos vazios e o título provisório")
    func failureOnAPendingCard() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)
        let card = try addLink(model)

        model.applyLinkPreviews([LinkPreviewUpdate(itemID: card.id, state: .failed(at: Self.noon, attempts: 1))])

        let saved = try #require(model.item(id: card.id))
        #expect(saved.title == "apple.com")
        #expect(saved.link == LinkInfo(url: try url("https://www.apple.com/mac"), preview: .failed(at: Self.noon, attempts: 1)))
    }

    // MARK: Cartões que não recebem

    @Test("Resultado de cartão apagado, de outro tipo ou desconhecido é ignorado sem mexer no mural")
    func updatesForMissingOrOtherKindsAreIgnored() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store)
        let card = try addLink(model)
        let sticky = try #require(model.board.items.first { $0.kind == .sticky })
        let folder = try #require(model.board.items.first { $0.kind == .folder })
        model.delete(card.id)
        let before = model.board

        model.applyLinkPreviews([
            ready(card.id, title: "Apagado", imageFile: "x.jpg"), ready(sticky.id, title: "Post-it", imageFile: "y.jpg"),
            ready(folder.id, title: "Pasta"), ready(UUID(), title: "Desconhecido"),
        ])

        #expect(model.board == before)
        #expect(model.item(id: card.id) == nil)
    }

    @Test("Um resultado ignorado não impede os outros do mesmo lote de serem aplicados")
    func ignoredUpdatesDoNotBlockTheBatch() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)
        let first = try addLink(model, "https://apple.com/mac")
        let second = try addLink(model, "https://swift.org")

        model.applyLinkPreviews([ready(UUID(), title: "Fantasma"), ready(first.id, title: "Um"), ready(second.id, title: "Dois")])
        #expect(try link(model, first.id).pageTitle == "Um" && link(model, second.id).pageTitle == "Dois")

        // O mesmo cartão duas vezes no lote: valem em sequência, e o último vence.
        model.applyLinkPreviews([ready(first.id, title: "Primeiro"), ready(first.id, title: "Segundo")])
        #expect(try link(model, first.id).pageTitle == "Segundo")
    }

    // MARK: Gravação

    @Test("Grava só quando algo mudou")
    func persistsOnlyWhenSomethingChanged() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)
        let card = try addLink(model)
        try FileManager.default.removeItem(at: store.fileURL)
        // Com uma pasta no lugar do board.json, qualquer gravação falharia e preencheria `lastError`.
        try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: true)
        model.lastError = nil

        model.applyLinkPreviews([])
        model.applyLinkPreviews([ready(UUID(), title: "Desconhecido")])
        model.applyLinkPreviews([LinkPreviewUpdate(itemID: card.id, state: .pending)])
        #expect(model.lastError == nil, "nada mudou, nada foi gravado")

        model.applyLinkPreviews([ready(card.id, title: "Apple")])
        #expect(model.lastError != nil, "controle: uma mudança tenta gravar")
    }

    @Test("Os campos aplicados reaparecem ao reabrir o mural")
    func appliedPreviewsSurviveReopen() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store)
        let folder = try #require(model.rootItems.first { $0.kind == .folder })
        let loose = try addLink(model, "https://www.apple.com/mac", summary: "Resumo do Safari")
        let inside = try #require(model.importLinks([LinkDraft(url: try url("https://swift.org"))], into: folder.id).first)
        let failed = try addLink(model, "https://fora-do-ar.example")

        model.applyLinkPreviews([
            ready(
                loose.id, title: "Apple Mac", site: "Apple", summary: "outro", image: "https://cdn.apple.com/mac.jpg", imageFile: "a.jpg",
                iconFile: "a.png"),
            ready(inside.id, title: "Swift.org", site: "Swift"),
            LinkPreviewUpdate(itemID: failed.id, state: .failed(at: Self.noon, attempts: 3)),
        ])
        #expect(model.lastError == nil)

        let reopened = BoardModel(store: store)
        let looseSaved = try #require(reopened.item(id: loose.id))
        #expect(looseSaved.title == "Apple Mac")
        #expect(looseSaved.link == model.item(id: loose.id)?.link)
        #expect(looseSaved.link?.summary == "Resumo do Safari" && looseSaved.link?.preview == .ready(fetchedAt: Self.noon))
        #expect(looseSaved.link?.previewImageFile == "a.jpg" && looseSaved.link?.iconFile == "a.png")
        let insideSaved = try #require(reopened.item(id: inside.id))
        #expect(insideSaved.title == "Swift.org" && insideSaved.parentID == folder.id && insideSaved.link?.siteName == "Swift")
        #expect(reopened.item(id: failed.id)?.link?.preview == .failed(at: Self.noon, attempts: 3))
    }

    @Test("Com gravação adiada o modelo muda na memória e deixa o disco para a sessão")
    func deferredPersistenceDoesNotWrite() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(board: Board(), store: store, persistence: .deferred)
        let card = try addLink(model)

        model.applyLinkPreviews([ready(card.id, title: "Apple")])

        #expect(model.item(id: card.id)?.title == "Apple")
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    // MARK: Pedidos

    @Test("Só entram os cartões que a política manda buscar, com as tentativas anteriores do estado de falha")
    func requestsFollowThePolicy() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store)
        let now = Self.noon.addingTimeInterval(86_400)
        let pending = try addLink(model, "https://apple.com/mac", image: "https://safari.example/capa.jpg")
        let done = try addLink(model, "https://swift.org")
        let recentFailure = try addLink(model, "https://recente.example")
        let oldFailure = try addLink(model, "https://antiga.example")
        let firstFailure = try addLink(model, "https://primeira.example")
        try setLink(model, done.id) { $0.preview = .ready(fetchedAt: now.addingTimeInterval(-86_400)) }
        try setLink(model, recentFailure.id) { $0.preview = .failed(at: now.addingTimeInterval(-600), attempts: 2) }
        try setLink(model, oldFailure.id) { $0.preview = .failed(at: now.addingTimeInterval(-3 * 3_600), attempts: 2) }
        try setLink(model, firstFailure.id) { $0.preview = .failed(at: now.addingTimeInterval(-3_600), attempts: 1) }
        let sticky = try #require(model.board.items.first { $0.kind == .sticky })
        let ids = [pending, done, recentFailure, oldFailure, firstFailure].map(\.id) + [sticky.id, UUID()]

        let requests = model.linkPreviewRequests(for: ids, now: now)

        #expect(requests.map(\.itemID) == [pending.id, oldFailure.id, firstFailure.id])
        #expect(requests.map(\.previousAttempts) == [0, 2, 1])
        #expect(requests.map(\.url.absoluteString) == ["https://apple.com/mac", "https://antiga.example", "https://primeira.example"])
        #expect(requests.map { $0.remoteImageURL?.absoluteString } == ["https://safari.example/capa.jpg", nil, nil])
    }

    @Test("Com force entram todos os cartões de link, pendentes, prontos ou com falha recente")
    func forceIncludesEveryLinkCard() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store)
        let now = Self.noon
        let done = try addLink(model, "https://swift.org")
        let recentFailure = try addLink(model, "https://recente.example")
        let pending = try addLink(model, "https://apple.com")
        try setLink(model, done.id) { $0.preview = .ready(fetchedAt: now) }
        try setLink(model, recentFailure.id) { $0.preview = .failed(at: now.addingTimeInterval(-10), attempts: 4) }
        let sticky = try #require(model.board.items.first { $0.kind == .sticky })
        let ids = [done.id, recentFailure.id, pending.id, sticky.id, UUID()]

        #expect(model.linkPreviewRequests(for: ids, now: now).map(\.itemID) == [pending.id])
        let forced = model.linkPreviewRequests(for: ids, now: now, force: true)
        #expect(forced.map(\.itemID) == [done.id, recentFailure.id, pending.id])
        #expect(forced.map(\.previousAttempts) == [0, 4, 0])
    }

    @Test("Os pedidos seguem a ordem recebida, sem repetir cartão, e ids que não são de link ficam de fora")
    func requestOrderAndDuplicates() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store)
        let first = try addLink(model, "https://apple.com")
        let second = try addLink(model, "https://swift.org")
        let third = try addLink(model, "https://example.com")

        #expect(model.linkPreviewRequests(for: [third.id, first.id, second.id]).map(\.itemID) == [third.id, first.id, second.id])
        #expect(model.linkPreviewRequests(for: [first.id, first.id, second.id, first.id]).map(\.itemID) == [first.id, second.id])
        #expect(model.linkPreviewRequests(for: []).isEmpty)
        #expect(model.linkPreviewRequests(for: [UUID()], force: true).isEmpty)
    }

    @Test("Cartão de link com endereço que não é da web nunca gera pedido")
    func nonWebLinkNeverMakesARequest() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)
        let card = try addLink(model)
        try setLink(model, card.id) { $0.url = URL(fileURLWithPath: "/etc/hosts") }

        #expect(model.linkPreviewRequests(for: [card.id]).isEmpty)
        #expect(model.linkPreviewRequests(for: [card.id], force: true).isEmpty)
    }

    // MARK: Arquivos em uso

    @Test("referencedLinkPreviewFiles reúne as imagens e os ícones de todos os cartões, inclusive os de dentro de pastas")
    func referencedFiles() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store)
        #expect(model.referencedLinkPreviewFiles.isEmpty, "controle: o mural de exemplo não tem links")
        let folder = try #require(model.rootItems.first { $0.kind == .folder })
        let both = try addLink(model, "https://apple.com")
        let onlyImage = try addLink(model, "https://swift.org")
        let none = try addLink(model, "https://example.com")
        let inside = try #require(model.importLinks([LinkDraft(url: try url("https://example.org"))], into: folder.id).first)
        let sharedName = try addLink(model, "https://example.net")
        try setLink(model, both.id) { ($0.previewImageFile, $0.iconFile) = ("a.jpg", "a.png") }
        try setLink(model, onlyImage.id) { $0.previewImageFile = "b.jpg" }
        try setLink(model, inside.id) { ($0.previewImageFile, $0.iconFile) = ("c.png", "c-icone.png") }
        try setLink(model, sharedName.id) { ($0.previewImageFile, $0.iconFile) = ("a.jpg", "a.png") }

        #expect(model.referencedLinkPreviewFiles == ["a.jpg", "a.png", "b.jpg", "c.png", "c-icone.png"])
        #expect(try link(model, none.id).previewImageFile == nil, "controle: o cartão sem arquivos não entra")
    }

    @Test("Os nomes aplicados por applyLinkPreviews passam a contar como em uso")
    func appliedFilesBecomeReferenced() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)
        let card = try addLink(model)
        #expect(model.referencedLinkPreviewFiles.isEmpty)

        model.applyLinkPreviews([ready(card.id, imageFile: "capa.jpg", iconFile: "icone.png")])
        #expect(model.referencedLinkPreviewFiles == ["capa.jpg", "icone.png"])

        model.applyLinkPreviews([ready(card.id, imageFile: "capa-nova.jpg")])
        #expect(model.referencedLinkPreviewFiles == ["capa-nova.jpg", "icone.png"], "o nome antigo deixa de contar e o sweep o recolhe")

        model.delete(card.id)
        #expect(model.referencedLinkPreviewFiles.isEmpty)
    }
}
