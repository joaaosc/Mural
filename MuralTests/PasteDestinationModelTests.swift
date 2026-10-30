import AppKit
import CoreGraphics
import Foundation
import MuralKit
import Testing

@testable import Mural

/// Uma biblioteca temporária com murais, o documento do editor e o modelo da galeria, com a entrega de verdade e o desenho das
/// capas trocado por um que não desenha nada.
@MainActor
private final class DestinationWorkspace {
    let directory: URL
    let library: BoardLibrary
    let preferences: UserDefaults
    let document = TextEditorDocument()
    let covers: BoardCoverService
    let delivery: BoardDelivery
    private let suiteName: String
    private(set) var ids: [String: BoardID] = [:]

    init(boards names: [String]) async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PasteDestination-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        library = BoardLibrary(rootDirectory: directory, discardPackage: { try FileManager.default.removeItem(at: $0) })
        for name in names {
            if case .saved(let id) = try await library.createNamedBoard(name) { ids[name] = id }
        }
        suiteName = "PasteDestinationTests-\(UUID().uuidString)"
        preferences = try #require(UserDefaults(suiteName: suiteName))
        covers = BoardCoverService(
            library: library, files: BoardCoverFiles(directory: directory.appendingPathComponent("Capas", isDirectory: true)),
            liveBoards: { [] }, linkPreviewFiles: { _ in nil }, render: { _, _, _ in nil })
        delivery = BoardDelivery(registry: BoardSessionRegistry(library: library), covers: covers)
    }

    func makeModel(now: @escaping () -> Date = Date.init) -> PasteDestinationModel {
        PasteDestinationModel(
            library: library, covers: covers, delivery: delivery, document: document, preferences: preferences, now: now)
    }

    func board(_ name: String) async throws -> Board {
        let entry = try #require(try await library.listSaved().first { $0.manifest.name == name })
        return try #require(try await library.readBoard(entry.route))
    }

    func itemsDirectory(_ name: String) async throws -> URL {
        let id = try #require(ids[name])
        let repository = try await library.repository(for: .saved(id))
        return await repository.packageURL(for: id).appendingPathComponent("Items", isDirectory: true)
    }

    func finish() async {
        await covers.waitUntilIdle()
        preferences.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}

@Suite("Galeria Colar no mural")
@MainActor
struct PasteDestinationModelTests {
    private func png() -> Data {
        let image = NSImage(size: NSSize(width: 16, height: 8), flipped: false) { rect in
            NSColor.blue.setFill()
            rect.fill()
            return true
        }
        return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    }

    @Test("A seleção inicial é o último destino do editor; sem ele, o mural mais recente")
    func initialSelection() async throws {
        let workspace = try await DestinationWorkspace(boards: ["Casa", "Obra", "Compras"])
        let obra = try #require(workspace.ids["Obra"])
        workspace.preferences.set(obra.rawValue.uuidString, forKey: PasteDestinationModel.lastDestinationKey)
        let model = workspace.makeModel()
        await model.load()
        #expect(model.selectedEntry?.manifest.id == obra)

        workspace.preferences.removeObject(forKey: PasteDestinationModel.lastDestinationKey)
        let fresh = workspace.makeModel()
        await fresh.load()
        #expect(fresh.selectedEntry != nil)
        await workspace.finish()
    }

    @Test("As setas andam pelos murais e param nas pontas; letras procuram pelo nome")
    func moveAndType() async throws {
        let workspace = try await DestinationWorkspace(boards: ["Casa", "Obra", "Compras"])
        let model = workspace.makeModel()
        await model.load()

        model.selectFirst()
        #expect(model.selection == 0)
        model.move(by: -1)
        #expect(model.selection == 0)
        model.move(by: 1)
        #expect(model.selection == 1)
        model.selectLast()
        #expect(model.selection == model.entries.count - 1)
        model.move(by: 5)
        #expect(model.selection == model.entries.count - 1)

        model.type("o")
        model.type("b")
        #expect(model.selectedEntry?.manifest.name == "Obra")
        await workspace.finish()
    }

    @Test("Os jeitos de colar vêm do texto; com cartão embutido, post-it e lista ficam desligados e a escolha é a nota")
    func kindsAndVetoes() async throws {
        let workspace = try await DestinationWorkspace(boards: ["Casa"])
        workspace.document.text = "Ligar para o marceneiro"
        let model = workspace.makeModel()
        await model.load()
        #expect(model.suggestion.suggested == .sticky && model.selectedKind == .sticky)

        model.moveKind(by: 1)
        #expect(model.selectedKind == .text)
        model.moveKind(by: 9)
        #expect(model.selectedKind == .text, "para na última que vale")

        workspace.document.text = "- ovos\n- leite"
        workspace.document.insertCards([.contact(ContactSnapshot(givenName: "Ana"))])
        await model.load()
        #expect(model.selectedKind == .text)
        #expect(model.suggestion.unavailable[.sticky] != nil && model.suggestion.unavailable[.checklist] != nil)
        model.selectKind(.sticky)
        #expect(model.selectedKind == .text, "um jeito desligado não se escolhe")
        #expect(model.selectableKinds == [.text])
        await workspace.finish()
    }

    @Test("Colar texto curto vira post-it, lembra o mural e não limpa o editor")
    func pastesASticky() async throws {
        let workspace = try await DestinationWorkspace(boards: ["Casa"])
        workspace.document.text = "Comprar pão"
        let model = workspace.makeModel()
        await model.load()

        #expect(await model.paste())

        #expect(model.status == .pasted("Colado em Casa"))
        #expect(model.lastDestination == workspace.ids["Casa"])
        #expect(workspace.document.text == "Comprar pão", "o editor continua com o texto")
        let sticky = try #require(try await workspace.board("Casa").items.first { $0.kind == .sticky })
        #expect(sticky.text == "Comprar pão")
        await workspace.finish()
    }

    @Test("Colar endereços cria um cartão de link por endereço")
    func pastesLinks() async throws {
        let workspace = try await DestinationWorkspace(boards: ["Casa"])
        workspace.document.text = "https://example.com/a\nhttps://example.org/b"
        let model = workspace.makeModel()
        await model.load()
        #expect(model.selectedKind == .links(count: 2))

        #expect(await model.paste())

        let links = try await workspace.board("Casa").items.filter { $0.kind == .link }
        #expect(links.count == 2)
        #expect(Set(links.compactMap { $0.link?.url.host }) == ["example.com", "example.org"])
        await workspace.finish()
    }

    @Test("Uma nota com cartão embutido e imagem vira um cartão de texto com os anexos, a imagem em Items/ e o texto citando os dois")
    func pastesANoteWithEmbeds() async throws {
        let workspace = try await DestinationWorkspace(boards: ["Casa"])
        let document = workspace.document
        document.text = "Visita à obra."
        document.insertCards([.contact(ContactSnapshot(givenName: "Fulana", familyName: "de Tal"))])
        document.insertImages([.data(png(), fileExtension: "png")])
        let model = workspace.makeModel()
        await model.load()
        #expect(model.selectedKind == .text)

        #expect(await model.paste())

        let note = try #require(try await workspace.board("Casa").items.first { $0.kind == .text })
        let text = try #require(note.text)
        let attachments = try #require(note.attachments)
        let card = try #require(attachments.first { $0.isCard })
        #expect(card.card == .contact(ContactSnapshot(givenName: "Fulana", familyName: "de Tal")))
        let imageName = NoteImageMarkup.referencedFileNames(in: text)
        #expect(imageName.count == 1 && attachments.contains { $0.fileName == imageName[0] })
        #expect(NoteImageMarkup.referencedCardIDs(in: text).count == 1)
        #expect(!text.contains("mural-colando"))
        let items = try await workspace.itemsDirectory("Casa")
        #expect(FileManager.default.fileExists(atPath: items.appendingPathComponent(imageName[0]).path))
        #expect(note.title == "Visita à obra.")
        await workspace.finish()
    }

    @Test("Mural apagado: colar falha, o editor fica como está e a galeria mostra o motivo")
    func failsWhenTheBoardIsGone() async throws {
        let workspace = try await DestinationWorkspace(boards: ["Casa"])
        workspace.document.text = "Comprar pão"
        let model = workspace.makeModel()
        await model.load()
        let entry = try #require(model.selectedEntry)
        try await workspace.library.deleteBoard(entry.route)

        #expect(await model.paste() == false)

        guard case .failed(let message) = model.status else {
            Issue.record("esperava uma falha, veio \(model.status)")
            return
        }
        #expect(!message.isEmpty)
        #expect(model.lastDestination == nil, "o destino só é lembrado quando o colar dá certo")
        #expect(workspace.document.text == "Comprar pão")
        await workspace.finish()
    }

    @Test("Return duas vezes cola uma vez só")
    func pastingTwiceCreatesOneCard() async throws {
        let workspace = try await DestinationWorkspace(boards: ["Casa"])
        workspace.document.text = "Comprar pão"
        let model = workspace.makeModel()
        await model.load()

        #expect(await model.paste())
        #expect(model.canPaste == false, "depois de colar, outro pedido não vale")
        #expect(await model.paste() == false)
        model.requestPaste()

        let cards = try await workspace.board("Casa").items.filter { $0.kind == .sticky }
        #expect(cards.count == 1)
        await workspace.finish()
    }

    @Test("O pedido de colar roda numa tarefa do modelo e um segundo pedido enquanto cola é ignorado")
    func requestPasteRunsInTheModelsOwnTask() async throws {
        let workspace = try await DestinationWorkspace(boards: ["Casa"])
        workspace.document.text = "Comprar pão"
        let model = workspace.makeModel()
        await model.load()

        model.requestPaste()
        #expect(model.status == .pasting)
        model.requestPaste()
        for _ in 0..<200 where model.status == .pasting { try await Task.sleep(for: .milliseconds(25)) }

        #expect(model.status == .pasted("Colado em Casa"))
        #expect(try await workspace.board("Casa").items.filter { $0.kind == .sticky }.count == 1)
        await workspace.finish()
    }

    @Test("O editor ganha um cartão com a galeria aberta: colar entrega a nota, nunca o texto com a linha do cartão")
    func staleKindsAreRefreshed() async throws {
        let workspace = try await DestinationWorkspace(boards: ["Casa"])
        workspace.document.text = "Comprar pão"
        let model = workspace.makeModel()
        await model.load()
        #expect(model.selectedKind == .sticky)

        workspace.document.insertCards([.contact(ContactSnapshot(givenName: "Ana"))])

        #expect(await model.paste())
        let board = try await workspace.board("Casa")
        #expect(board.items.allSatisfy { $0.kind != .sticky })
        let note = try #require(board.items.first { $0.kind == .text })
        #expect(note.attachments?.contains { $0.isCard } == true)
        await workspace.finish()
    }

    @Test("Imagem perdida deixa um aviso no colar que deu certo, sem linha nem arquivo")
    func lostImageWarns() async throws {
        let workspace = try await DestinationWorkspace(boards: ["Casa"])
        workspace.document.text = "Foto:"
        workspace.document.insertImages([.data(Data([1, 2, 3]), fileExtension: "png")])
        let model = workspace.makeModel()
        await model.load()

        #expect(await model.paste())

        #expect(model.warning == "Uma imagem não pôde ser colada.")
        let note = try #require(try await workspace.board("Casa").items.first { $0.kind == .text })
        #expect(!(note.text ?? "").contains("mural-colando"))
        let items = try await workspace.itemsDirectory("Casa")
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: items.path)) ?? []).isEmpty)
        await workspace.finish()
    }

    @Test("Imagem na nota de um mural fechado: o arquivo existe em Items/ depois da entrega")
    func imageOnAClosedBoardIsStored() async throws {
        let workspace = try await DestinationWorkspace(boards: ["Casa"])
        workspace.document.text = "Foto:"
        workspace.document.insertImages([.data(png(), fileExtension: "png")])
        let model = workspace.makeModel()
        await model.load()

        #expect(await model.paste())

        let note = try #require(try await workspace.board("Casa").items.first { $0.kind == .text })
        let names = NoteImageMarkup.referencedFileNames(in: note.text ?? "")
        #expect(names.count == 1)
        let items = try await workspace.itemsDirectory("Casa")
        #expect(FileManager.default.fileExists(atPath: items.appendingPathComponent(names[0]).path))
        await workspace.finish()
    }

    /// Espera o colar pedido terminar, no modelo.
    private func waitUntilPasted(_ model: PasteDestinationModel) async throws {
        for _ in 0..<400 {
            if case .pasted = model.status { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("o colar não terminou: \(model.status)")
    }

    @Test("Colar como Card de texto pede o título antes, com o título do texto já preenchido, e o cartão fica com o escolhido")
    func textCardAsksForTheTitle() async throws {
        let workspace = try await DestinationWorkspace(boards: ["Obra"])
        workspace.document.text = "Visita à obra: medir a parede\n\nTrazer a trena e o nível."
        let model = workspace.makeModel()
        await model.load()
        model.selectKind(.text)

        model.requestPaste()
        #expect(model.titleDraft == "Visita à obra: medir a parede")
        #expect(model.status == .idle, "nada é colado antes da resposta")

        model.editTitle("  Parede norte  ")
        model.confirmTitle()
        #expect(model.titleDraft == nil)
        try await waitUntilPasted(model)
        let items = try await workspace.board("Obra").items
        #expect(items.map(\.title) == ["Parede norte"])
        #expect(items.first?.kind == .text)
        #expect(items.first?.text == workspace.document.text, "o título não muda o texto")
        await workspace.finish()
    }

    @Test("Cancelar a pergunta do título volta à galeria sem colar")
    func cancellingTheTitlePastesNothing() async throws {
        let workspace = try await DestinationWorkspace(boards: ["Obra"])
        workspace.document.text = "Texto do card"
        let model = workspace.makeModel()
        await model.load()
        model.selectKind(.text)
        model.requestPaste()
        model.cancelTitle()
        #expect(model.titleDraft == nil && model.status == .idle && model.canPaste)
        model.confirmTitle()
        #expect(model.status == .idle, "sem pergunta aberta, confirmar não cola")
        #expect(try await workspace.board("Obra").items.isEmpty)
        await workspace.finish()
    }

    @Test("Fechada a pergunta, o campo que entrega o texto mais uma vez não a reabre")
    func lateFieldCommitDoesNotReopenTheQuestion() async throws {
        let workspace = try await DestinationWorkspace(boards: ["Obra"])
        workspace.document.text = "Texto do card"
        let model = workspace.makeModel()
        await model.load()
        model.selectKind(.text)
        model.requestPaste()
        model.cancelTitle()
        model.editTitle("Texto do card")
        #expect(model.titleDraft == nil)

        model.requestPaste()
        model.confirmTitle()
        model.editTitle("Texto do card")
        #expect(model.titleDraft == nil)
        try await waitUntilPasted(model)
        await workspace.finish()
    }

    @Test("Título apagado deixa o cartão com o título tirado do texto")
    func emptyTitleKeepsTheOneFromTheText() async throws {
        let workspace = try await DestinationWorkspace(boards: ["Obra"])
        workspace.document.text = "Primeira linha\n\nSegunda linha."
        let model = workspace.makeModel()
        await model.load()
        model.selectKind(.text)
        model.requestPaste()
        model.editTitle("   ")
        model.confirmTitle()
        try await waitUntilPasted(model)
        #expect(try await workspace.board("Obra").items.map(\.title) == ["Primeira linha"])
        await workspace.finish()
    }

    @Test("O título vale também para a nota com cartão embutido")
    func titleOnANoteWithAnEmbed() async throws {
        let workspace = try await DestinationWorkspace(boards: ["Obra"])
        workspace.document.text = "Com contato\n\n"
        workspace.document.insertCards([.contact(ContactSnapshot(givenName: "Ana"))])
        let model = workspace.makeModel()
        await model.load()
        model.requestPaste()
        #expect(model.titleDraft == "Com contato")
        model.editTitle("Equipe")
        model.confirmTitle()
        try await waitUntilPasted(model)
        let item = try #require(try await workspace.board("Obra").items.first)
        #expect(item.title == "Equipe" && item.attachments?.count == 1)
        await workspace.finish()
    }

    @Test("Post-it, lista e links colam sem pedir título")
    func otherKindsDoNotAsk() async throws {
        let workspace = try await DestinationWorkspace(boards: ["Obra"])
        workspace.document.text = "Curto"
        let model = workspace.makeModel()
        await model.load()
        #expect(model.selectedKind == .sticky)
        model.requestPaste()
        #expect(model.titleDraft == nil)
        try await waitUntilPasted(model)
        await workspace.finish()
    }

    @Test("Os textos dos jeitos de colar")
    func wording() {
        #expect(PasteKindWording.title(of: .sticky) == "Sticker")
        #expect(PasteKindWording.title(of: .links(count: 1)) == "Link")
        #expect(PasteKindWording.title(of: .links(count: 3)) == "3 links")
        #expect(PasteKindWording.summary(unavailable: nil, board: "Obra") == "em Obra")
        #expect(PasteKindWording.summary(unavailable: "Motivo", board: "Obra") == "Motivo")
    }
}
