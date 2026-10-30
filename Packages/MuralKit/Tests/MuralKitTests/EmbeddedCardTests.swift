import Foundation
import StretchText
import Testing

@testable import MuralKit

@MainActor
@Suite("Cartões embutidos em notas")
struct EmbeddedCardTests {
    private let cardID = UUID(uuidString: "5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01")!
    private let otherID = UUID(uuidString: "7C1D5E3F-9D1C-4C2A-8E86-4F2B8A3BAD02")!

    private func music() -> MusicSnapshot {
        MusicSnapshot(
            kind: .song, catalogID: "123", storefront: "br", libraryID: "L1", url: URL(string: "https://music.apple.com/br/song/123"),
            title: "Faixa", subtitle: "Artista", artworkFile: "capa.jpg")
    }

    private func reminder() -> ReminderSnapshot {
        ReminderSnapshot(identifier: "R1", title: "Comprar pão")
    }

    private func link() -> LinkInfo {
        LinkInfo(
            url: URL(string: "https://apple.com/mac")!, pageTitle: "Mac", previewImageFile: "A1.jpg", iconFile: "B2.png",
            preview: .ready(fetchedAt: Date(timeIntervalSince1970: 100)))
    }

    private func attachment(_ id: UUID, _ card: EmbeddedCard) -> NoteAttachment {
        NoteAttachment(fileName: NoteImageMarkup.cardAttachmentName(for: id), pixelWidth: 0, pixelHeight: 0, card: card)
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MuralCard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Formato

    @Test("Anexo só de imagem grava exatamente o JSON de antes, sem a chave card")
    func imageOnlyJSONIsUnchanged() throws {
        let name = "5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01.png"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(NoteAttachment(fileName: name, pixelWidth: 4, pixelHeight: 3))
        let expected = #"{"fileName":"\#(name)","pixelHeight":3,"pixelWidth":4}"#
        #expect(String(decoding: data, as: UTF8.self) == expected)

        let decoded = try JSONDecoder().decode(NoteAttachment.self, from: Data(expected.utf8))
        #expect(decoded.card == nil && !decoded.isCard)
        #expect(try encoder.encode(decoded) == data)

        let item = BoardItem(kind: .text, title: "N", attachments: [decoded])
        let board = Board(items: [item])
        #expect(board.formatVersion == 5)
        let json = String(decoding: try encoder.encode(board), as: UTF8.self)
        #expect(!json.contains("\"card\""))
    }

    @Test("Cada tipo de cartão embutido faz a viagem de ida e volta com a forma estável")
    func roundTrip() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for (card, kind) in [
            (EmbeddedCard.music(music()), "music"), (.reminder(reminder()), "reminder"), (.link(link()), "link"),
        ] {
            let source = attachment(cardID, card)
            let data = try encoder.encode(source)
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let inner = try #require(object["card"] as? [String: Any])
            #expect(inner["kind"] as? String == kind)
            #expect(inner[kind] is [String: Any])
            #expect(try JSONDecoder().decode(NoteAttachment.self, from: data) == source)
        }
    }

    @Test("Tipo embutido desconhecido é recusado")
    func unknownKindThrows() {
        let json = #"{"fileName":"\#(cardID.uuidString).card","pixelWidth":0,"pixelHeight":0,"card":{"kind":"futuro","futuro":{}}}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(NoteAttachment.self, from: Data(json.utf8)) }
    }

    @Test("Título e tipo do cartão embutido")
    func titleAndKind() {
        #expect(EmbeddedCard.music(music()).title == "Faixa" && EmbeddedCard.music(music()).itemKind == .music)
        #expect(EmbeddedCard.reminder(reminder()).title == "Comprar pão" && EmbeddedCard.reminder(reminder()).itemKind == .reminder)
        #expect(EmbeddedCard.link(link()).title == "Mac" && EmbeddedCard.link(link()).itemKind == .link)
        var bare = link()
        bare.pageTitle = nil
        #expect(EmbeddedCard.link(bare).title == WebLink.displayHost(of: bare.url))
    }

    @Test("A versão 13 só aparece com um cartão embutido")
    func versionThirteen() {
        let plain = BoardItem(
            kind: .text, title: "N", attachments: [NoteAttachment(fileName: "\(cardID.uuidString).png", pixelWidth: 1, pixelHeight: 1)])
        #expect(Board.currentFormatVersion == 14)
        #expect(Board(items: [plain]).requiredFormatVersion == 5)
        let withCard = BoardItem(kind: .text, title: "N", attachments: [attachment(cardID, .reminder(reminder()))])
        #expect(Board(items: [plain, withCard]).requiredFormatVersion == 13)
        #expect(Board(items: [withCard]).formatVersion == 13)
    }

    // MARK: Markdown

    @Test("cardLine limpa o título; referencedCardIDs lê só linhas mural-card:, sem repetição e fora de cerca")
    func markup() {
        let id = cardID
        #expect(NoteImageMarkup.cardLine(id: id, title: " A]\nB ") == "![A B](mural-card:\(id.uuidString))")
        #expect(NoteImageMarkup.cardLine(id: id, title: " ]\n ") == "![Cartão](mural-card:\(id.uuidString))")
        let image = "5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C09.png"
        let text = [
            NoteImageMarkup.cardLine(id: otherID, title: "Um"), NoteImageMarkup.line(fileName: image),
            NoteImageMarkup.cardLine(id: id, title: "Dois"), NoteImageMarkup.cardLine(id: otherID, title: "Um de novo"),
            "```\n" + NoteImageMarkup.cardLine(id: UUID(), title: "Em código") + "\n```", "![x](mural-card:nao-e-uuid)",
        ].joined(separator: "\n\n")
        #expect(NoteImageMarkup.referencedCardIDs(in: text) == [otherID, id])
        #expect(NoteImageMarkup.referencedFileNames(in: text) == [image])
        #expect(NoteImageMarkup.isCardSource("mural-card:x") && !NoteImageMarkup.isCardSource(image))
        #expect(NoteImageMarkup.cardID(inSource: "mural-card:\(id.uuidString)") == id)
        #expect(NoteImageMarkup.cardID(inSource: "mural-card:x") == nil)
    }

    @Test("Nome de anexo aceita <UUID>.card, e referencedFileNames nunca o devolve")
    func attachmentNames() {
        let name = NoteImageMarkup.cardAttachmentName(for: cardID)
        #expect(name == "\(cardID.uuidString).card")
        #expect(!NoteImageMarkup.isAttachmentName(name) && NoteImageMarkup.isCardAttachmentName(name))
        #expect(!NoteImageMarkup.isCardAttachmentName("\(cardID.uuidString).png"))
        #expect(!NoteImageMarkup.isCardAttachmentName("x.card"))
        #expect(!NoteImageMarkup.isCardAttachmentName("\(cardID.uuidString).CARD"))
        #expect(!NoteImageMarkup.isCardAttachmentName("../\(cardID.uuidString).card"))
        #expect(!NoteImageMarkup.isAttachmentName("x.card") && !NoteImageMarkup.isAttachmentName(".card"))
        let both = NoteImageMarkup.references(
            in: "![a](\(name))\n\n![b](\(cardID.uuidString).png)\n\n![c](mural-card:\(otherID.uuidString))")
        #expect(both.fileNames == ["\(cardID.uuidString).png"] && both.cardIDs == [otherID])
        #expect(NoteImageMarkup.referencedFileNames(in: "![a](\(name))").isEmpty)
        #expect(attachment(cardID, .reminder(reminder())).cardID == cardID)
        #expect(NoteAttachment(fileName: name, pixelWidth: 0, pixelHeight: 0).cardID == nil)
    }

    // MARK: Cartão

    @Test("assetFileNames exclui cartões embutidos; embeddedCards e embeddedCard(id:) os devolvem")
    func assetsExcludeCards() {
        let png = NoteAttachment(fileName: "\(otherID.uuidString).png", pixelWidth: 2, pixelHeight: 2)
        let card = attachment(cardID, .music(music()))
        let text = NoteImageMarkup.line(fileName: png.fileName) + "\n\n" + NoteImageMarkup.cardLine(id: cardID, title: "Faixa")
        let item = BoardItem(kind: .text, title: "N", text: text, attachments: [card, png])
        #expect(item.assetFileNames == [png.fileName])
        #expect(item.requiredAssetFileNames == [png.fileName])
        #expect(item.embeddedCards == [card])
        #expect(item.embeddedCard(id: cardID) == .music(music()))
        #expect(item.embeddedCard(id: otherID) == nil)
    }

    @Test("Reconciliar mantém o cartão citado, solta o não citado e nunca o lista como arquivo removido")
    func reconcileCards() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = BoardModel(board: Board(), store: BoardStore(directory: directory), persistence: .immediate)
        let note = model.createNote()
        let kept = attachment(cardID, .reminder(reminder()))
        let dropped = attachment(otherID, .link(link()))
        #expect(model.addNoteAttachment(kept, to: note.id) && model.addNoteAttachment(dropped, to: note.id))
        model.updateNote(note.id, title: "Nota", text: NoteImageMarkup.cardLine(id: cardID, title: "Lembrete"))
        #expect(model.item(id: note.id)?.attachments == [kept])
        #expect(model.noteImageURL(named: kept.fileName) == nil)
        model.updateNote(note.id, title: "Nota", text: "Sem cartões")
        #expect(model.item(id: note.id)?.attachments == nil)
        let saved = try #require(try BoardStore(directory: directory).load())
        #expect(saved.item(id: note.id)?.attachments == nil)
    }

    @Test("Reconciliar mantém só o primeiro anexo de cada nome")
    func reconcileDropsDuplicateNames() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = BoardModel(board: Board(), store: BoardStore(directory: directory), persistence: .immediate)
        let note = model.createNote()
        let first = attachment(cardID, .reminder(reminder()))
        var second = first
        second.card = .reminder(ReminderSnapshot(identifier: "", title: "Outro"))
        var item = try #require(model.item(id: note.id))
        item.attachments = [first, second]
        model.board.update(item)
        model.updateNote(note.id, title: "Nota", text: NoteImageMarkup.cardLine(id: cardID, title: "Lembrete"))
        #expect(model.item(id: note.id)?.attachments == [first])
    }

    // MARK: Compartilhamento

    @Test("shared tira as partes locais do link e da música embutidos; o lembrete fica como está")
    func sharedStripsEmbeddedLocalParts() {
        let item = BoardItem(
            kind: .text, title: "N",
            attachments: [
                attachment(cardID, .link(link())), attachment(otherID, .music(music())),
                attachment(UUID(), .reminder(reminder())),
            ])
        let result = SharedFieldPolicy.shared(item)
        guard case .link(let strippedLink)? = result.attachments?[0].card,
            case .music(let strippedMusic)? = result.attachments?[1].card
        else {
            Issue.record("tipos mudaram")
            return
        }
        #expect(strippedLink.previewImageFile == nil && strippedLink.iconFile == nil && strippedLink.preview == .pending)
        #expect(strippedLink.pageTitle == "Mac")
        #expect(strippedMusic.artworkFile == nil && strippedMusic.libraryID == nil && strippedMusic.title == "Faixa")
        #expect(result.attachments?[2] == item.attachments?[2])
    }

    @Test("preservingLocalFields devolve as partes locais pelo nome do anexo, só se for o mesmo link ou a mesma música")
    func preservingRestoresEmbeddedLocalParts() {
        let local = BoardItem(
            kind: .text, title: "N", attachments: [attachment(cardID, .link(link())), attachment(otherID, .music(music()))])
        let incoming = SharedFieldPolicy.shared(local)
        let restored = SharedFieldPolicy.preservingLocalFields(of: local, in: incoming)
        #expect(restored.attachments == local.attachments)

        var changedLink = link()
        changedLink.url = URL(string: "https://outro.example.com")!
        var changedMusic = music()
        changedMusic.catalogID = "999"
        let different = BoardItem(
            id: local.id, kind: .text, title: "N",
            attachments: [attachment(cardID, .link(changedLink)), attachment(otherID, .music(changedMusic))])
        let result = SharedFieldPolicy.preservingLocalFields(of: local, in: different)
        #expect(result.attachments == SharedFieldPolicy.shared(different).attachments)
    }

    // MARK: Exportação

    @Test("NoteExport devolve .card quando a nota guarda o cartão e um parágrafo quando não")
    func exportCard() {
        let card = EmbeddedCard.music(music())
        let text =
            "Antes.\n\n" + NoteImageMarkup.cardLine(id: cardID, title: "Faixa") + "\n\n"
            + NoteImageMarkup.cardLine(id: otherID, title: "Sumiu")
        let item = BoardItem(kind: .text, title: "", text: text, attachments: [attachment(cardID, card)])
        let blocks = NoteExport.blocks(for: item)
        #expect(blocks.contains(.card(card, title: "Faixa")))
        #expect(blocks.contains(.paragraph("Sumiu")))
    }

    // MARK: StretchText

    @Test("A linha do cartão é um bloco de imagem que não dobra, e os parágrafos dobram como antes")
    func foldingTreatsCardLineAsImage() {
        let line = NoteImageMarkup.cardLine(id: cardID, title: "Música")
        let text = "Primeira frase. Segunda frase.\n\n\(line)\n\nTerceira frase. Quarta frase."
        let segments = TextSegmenter.segment(text).segments
        let images = segments.filter { $0.kind == .image }
        #expect(images.count == 1 && images[0].text == line && !images[0].isFoldable)
        #expect(segments.filter(\.isFoldable).count == 2)
        let result = NoteFolding.fold(text, record: nil)
        #expect(result.document.stretchIDs.count == 2)
    }
}
