import AppKit
import CoreGraphics
import Foundation
import MuralKit
import Testing

@testable import Mural

/// O relógio da busca por letras: só anda quando o teste manda.
@MainActor
private final class PanelClock {
    private(set) var date = Date(timeIntervalSinceReferenceDate: 0)

    func advance(by seconds: TimeInterval) {
        date = date.addingTimeInterval(seconds)
    }
}

/// Uma biblioteca temporária com murais, as preferências e a pasta de capas de um teste, e os modelos feitos sobre elas.
///
/// O serviço de capas é o de verdade, com o desenho trocado por um que não desenha nada: o que se confere é quais capas
/// ele foi chamado a fazer, e em que ordem. A área de transferência é sempre uma nomeada só do teste: a geral nunca é
/// tocada.
@MainActor
private final class PanelWorkspace {
    let directory: URL
    let library: BoardLibrary
    let registry: BoardSessionRegistry
    let preferences: UserDefaults
    private let suiteName: String
    private let ids: [String: BoardID]
    private var services: [BoardCoverService] = []
    private var pasteboards: [NSPasteboard] = []
    /// Os murais de que o serviço começou a fazer a capa, na ordem em que começou.
    private(set) var coverOrder: [BoardID] = []

    var coversDirectory: URL {
        directory.appendingPathComponent("BoardCovers", isDirectory: true)
    }

    private init(
        directory: URL, library: BoardLibrary, registry: BoardSessionRegistry, preferences: UserDefaults, suiteName: String,
        ids: [String: BoardID]
    ) {
        self.directory = directory
        self.library = library
        self.registry = registry
        self.preferences = preferences
        self.suiteName = suiteName
        self.ids = ids
    }

    /// Cria a biblioteca e os murais, um depois do outro: o último é o editado mais recentemente.
    static func make(boards names: [String]) async throws -> PanelWorkspace {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MenuBarPanelModel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Mural excluído nos testes é apagado, não vai para o Lixo de quem roda os testes.
        let library = BoardLibrary(rootDirectory: directory, discardPackage: { url in try FileManager.default.removeItem(at: url) })
        var ids: [String: BoardID] = [:]
        for name in names {
            guard case .saved(let id) = try await library.createNamedBoard(name) else {
                Issue.record("O mural \(name) não foi criado como mural salvo")
                continue
            }
            ids[name] = id
        }
        let suiteName = "MenuBarPanelModelTests-\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: suiteName))
        return PanelWorkspace(
            directory: directory, library: library, registry: BoardSessionRegistry(library: library), preferences: preferences,
            suiteName: suiteName, ids: ids)
    }

    func boardID(_ name: String) throws -> BoardID {
        try #require(ids[name], "O mural \(name) não foi criado")
    }

    /// Uma área de transferência nomeada só deste teste, vazia.
    func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("mural-painel-teste-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboards.append(pasteboard)
        return pasteboard
    }

    /// Um leitor da área de transferência dada, com o comportamento de acesso trocado: o aviso "Permitir colar?" só
    /// existe na área de transferência geral.
    func makeReader(_ pasteboard: NSPasteboard, _ behavior: NSPasteboard.AccessBehavior) -> ClipboardReader {
        ClipboardReader(pasteboard: pasteboard, accessBehavior: { _ in behavior })
    }

    /// Um modelo novo sobre a mesma biblioteca, as mesmas preferências e a mesma pasta de capas. Sem `reader`, a área de
    /// transferência é uma vazia.
    func makeModel(
        activeBoard: BoardID? = nil, reader: ClipboardReader? = nil, editor: PasteEditor? = nil,
        now: @escaping () -> Date = Date.init
    ) -> MenuBarPanelModel {
        let covers = BoardCoverService(
            library: library,
            files: BoardCoverFiles(directory: coversDirectory),
            liveBoards: { [] },
            linkPreviewFiles: { [weak self] id in
                self?.coverOrder.append(id)
                return nil
            },
            render: { _, _, _ in nil })
        services.append(covers)
        return MenuBarPanelModel(
            library: library, covers: covers, activeBoard: { activeBoard },
            reader: reader ?? makeReader(makePasteboard(), .alwaysAllow),
            delivery: BoardDelivery(registry: registry, covers: covers), editor: editor, preferences: preferences,
            now: now)
    }

    /// O app de edição de mentira que os testes de edição usam.
    static let editorApp = PasteEditorApp(
        name: "Editor Teste", bundleIdentifier: "com.exemplo.Teste", url: URL(filePath: "/Applications/Teste.app"))

    /// Uma edição antes de colar com as pastas dentro da pasta do teste, que o `finish()` apaga.
    func makeEditor(launcher: any PasteEditorLaunching) -> PasteEditor {
        let roots = PasteEditFiles.Roots(
            inside: directory.appendingPathComponent("PasteEdits", isDirectory: true),
            visible: directory.appendingPathComponent("PasteEditsVisible", isDirectory: true))
        return PasteEditor(roots: roots, launcher: launcher, resolve: { _ in Self.editorApp })
    }

    /// Põe um arquivo comum no lugar da pasta `Boards`: a biblioteca não consegue mais listar os murais.
    func replaceBoardsFolderWithAFile() throws {
        let boards = directory.appendingPathComponent("Boards", isDirectory: false)
        try? FileManager.default.removeItem(at: boards)
        try Data("isto não é uma pasta".utf8).write(to: boards)
    }

    /// Espera o trabalho de capas terminar e apaga o que o teste criou.
    func finish() async {
        for service in services {
            await service.waitUntilIdle()
        }
        preferences.removePersistentDomain(forName: suiteName)
        for pasteboard in pasteboards { pasteboard.releaseGlobally() }
        try? FileManager.default.removeItem(at: directory)
    }
}

/// O estado do painel da barra de menus: a lista e o mural do centro, o teclado de letras, o destino lembrado, as capas
/// pedidas e o que acontece ao abrir. Sem desenhar nada.
@Suite("Estado do painel da barra de menus")
@MainActor
struct MenuBarPanelModelTests {
    private func makeImage() throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: 8, height: 5, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 5))
        return try #require(context.makeImage())
    }

    // MARK: Lista e mural inicial

    @Test("A lista segue a ordem da biblioteca; o centro é o último destino, senão a aba ativa, senão o mais recente")
    func listKeepsLibraryOrderAndCenterFollowsDestinationThenActiveBoardThenNewest() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Ideias", "Viagem", "Trabalho"])
        let ideias = try workspace.boardID("Ideias")
        let viagem = try workspace.boardID("Viagem")

        // Sem destino nem aba ativa: o editado mais recentemente. "Trabalho" foi o último a ser criado.
        let plain = workspace.makeModel()
        await plain.load()
        #expect(plain.isLoaded)
        #expect(plain.loadError == nil)
        #expect(plain.entries.map(\.manifest.name) == ["Ideias", "Trabalho", "Viagem", "Rascunho de exemplo"])
        #expect(plain.selectedEntry?.manifest.name == "Trabalho")

        // Com um mural na aba ativa, ele vence o mais recente.
        let withActiveBoard = workspace.makeModel(activeBoard: viagem)
        await withActiveBoard.load()
        #expect(withActiveBoard.selectedEntry?.manifest.name == "Viagem")

        // Com um último destino, ele vence a aba ativa.
        let withDestination = workspace.makeModel(activeBoard: viagem)
        withDestination.rememberDestination(ideias)
        await withDestination.load()
        #expect(withDestination.selectedEntry?.manifest.name == "Ideias")

        await workspace.finish()
    }

    // MARK: Seleção

    @Test("Andar para nas pontas, e selecionar fora da lista fica preso a ela")
    func moveStopsAtTheEndsAndSelectIsClamped() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Ideias", "Viagem", "Trabalho"])
        let model = workspace.makeModel()

        // Antes de carregar a lista está vazia: não há o que selecionar, e nada quebra.
        model.select(3)
        model.move(by: 1)
        model.type("v")
        #expect(model.selection == 0)
        #expect(model.selectedEntry == nil)

        await model.load()
        let last = model.entries.count - 1
        model.select(0)
        model.move(by: -1)
        #expect(model.selection == 0, "antes do primeiro não há nada")
        model.move(by: 1)
        #expect(model.selection == 1)
        for _ in 0...last + 2 {
            model.move(by: 1)
        }
        #expect(model.selection == last, "depois do último também não, e não dá a volta")
        model.move(by: -1)
        #expect(model.selection == last - 1)

        model.select(99)
        #expect(model.selection == last)
        model.select(-4)
        #expect(model.selection == 0)

        await workspace.finish()
    }

    // MARK: Busca por letras

    @Test("As letras digitadas sem pausa se juntam, e depois de uma pausa a busca recomeça")
    func typedLettersJoinAndRestartAfterAPause() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Ideias", "Viagem", "Trabalho"])
        let clock = PanelClock()
        let model = workspace.makeModel(now: { clock.date })
        await model.load()
        model.select(0)

        model.type("v")
        #expect(model.selectedEntry?.manifest.name == "Viagem")

        clock.advance(by: 0.5)
        model.type("i")
        // Juntas, "vi" ainda é Viagem. Se cada letra recomeçasse a busca, o "i" iria para Ideias.
        #expect(model.selectedEntry?.manifest.name == "Viagem")

        clock.advance(by: 1.5)
        model.type("t")
        // Depois da pausa, "t" acha Trabalho. Se a busca continuasse, "vit" não acharia nada e ficaria em Viagem.
        #expect(model.selectedEntry?.manifest.name == "Trabalho")

        await workspace.finish()
    }

    @Test("Uma pausa de exatamente o limite ainda não recomeça a busca; só uma maior")
    func aPauseOfExactlyTheLimitKeepsTheSearch() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Ideias", "Viagem", "Trabalho"])
        let clock = PanelClock()
        let model = workspace.makeModel(now: { clock.date })
        await model.load()
        model.select(0)

        model.type("v")
        clock.advance(by: MenuBarPanelModel.typingPause)
        model.type("i")
        #expect(model.selectedEntry?.manifest.name == "Viagem", "com a pausa no limite, \"vi\" continua juntas")

        clock.advance(by: MenuBarPanelModel.typingPause + 0.01)
        model.type("i")
        #expect(model.selectedEntry?.manifest.name == "Ideias", "passando do limite, o \"i\" é uma busca nova")

        await workspace.finish()
    }

    // MARK: Destino lembrado

    @Test("Lembrar o destino grava o identificador, e um modelo novo o lê; um valor que não é identificador não conta")
    func rememberedDestinationSurvivesANewModel() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Ideias", "Viagem"])
        let viagem = try workspace.boardID("Viagem")
        let first = workspace.makeModel()
        #expect(first.lastDestination == nil)

        first.rememberDestination(viagem)

        #expect(first.lastDestination == viagem)
        #expect(workspace.preferences.string(forKey: MenuBarPanelModel.lastDestinationKey) == viagem.rawValue.uuidString)
        #expect(workspace.makeModel().lastDestination == viagem, "um modelo novo, com as mesmas preferências")

        workspace.preferences.set("isto não é um identificador", forKey: MenuBarPanelModel.lastDestinationKey)
        #expect(workspace.makeModel().lastDestination == nil)

        await workspace.finish()
    }

    // MARK: Falha na listagem

    @Test("Se a biblioteca não pode ser lida, o erro aparece, a lista fica vazia e nenhuma capa é apagada")
    func failedListingReportsTheErrorAndKeepsTheCovers() async throws {
        let workspace = try await PanelWorkspace.make(boards: [])
        try workspace.replaceBoardsFolderWithAFile()
        let files = BoardCoverFiles(directory: workspace.coversDirectory)
        let stray = BoardID()
        try files.store(try makeImage(), for: stray, revision: 1)
        let model = workspace.makeModel()

        await model.load()
        await model.covers.waitUntilIdle()

        #expect(model.loadError?.isEmpty == false)
        #expect(model.entries.isEmpty)
        #expect(model.isLoaded)
        #expect(files.latest(for: stray) != nil, "sem poder ler a biblioteca não se sabe que murais existem: nada é apagado")

        // Sem murais, selecionar e andar não fazem nada.
        model.select(2)
        model.move(by: 1)
        #expect(model.selection == 0)

        await workspace.finish()
    }

    @Test("Com a biblioteca lida, as capas de murais que não existem mais são apagadas")
    func successfulListingSweepsTheCoversOfMissingBoards() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Ideias"])
        let files = BoardCoverFiles(directory: workspace.coversDirectory)
        let gone = BoardID()
        try files.store(try makeImage(), for: gone, revision: 1)
        let model = workspace.makeModel()

        await model.load()
        await model.covers.waitUntilIdle()

        #expect(model.loadError == nil)
        #expect(files.latest(for: gone) == nil, "a limpeza existe: é o que dá sentido ao teste anterior")

        await workspace.finish()
    }

    // MARK: Capas

    @Test("As capas são pedidas a partir do mural do centro, para fora, ao carregar e a cada seleção")
    func coversAreRequestedFromTheCenterOutward() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Ideias", "Viagem", "Trabalho"])
        let model = workspace.makeModel()

        await model.load()
        await model.covers.waitUntilIdle()
        // O centro é "Trabalho" (índice 1): ele, o seguinte, o anterior e, por fim, o último.
        let fromTheMiddle = [1, 2, 0, 3].map { model.entries[$0].manifest.id }
        #expect(workspace.coverOrder == fromTheMiddle)

        let alreadyDrawn = workspace.coverOrder.count
        model.select(3)
        await model.covers.waitUntilIdle()
        let fromTheEnd = [3, 2, 1, 0].map { model.entries[$0].manifest.id }
        #expect(Array(workspace.coverOrder.dropFirst(alreadyDrawn)) == fromTheEnd)

        await workspace.finish()
    }

    // MARK: Abrir

    @Test("Abrir um mural seleciona a aba dele, devolve o teclado ao mural e lembra o destino")
    func openSelectsTheBoardTabAndRemembersTheDestination() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Ideias", "Viagem"])
        let model = workspace.makeModel()
        await model.load()
        let tabs = MuralTabs(registry: BoardSessionRegistry(library: workspace.library))
        let ideias = try workspace.boardID("Ideias")
        let viagem = try workspace.boardID("Viagem")
        let ideiasIndex = try #require(model.entries.firstIndex { $0.manifest.id == ideias })
        let viagemIndex = try #require(model.entries.firstIndex { $0.manifest.id == viagem })
        let focusRequests = tabs.boardFocusRequest

        model.open(ideiasIndex, in: tabs)

        #expect(tabs.selected?.boardID == ideias)
        #expect(tabs.tabs.count == 1)
        #expect(model.lastDestination == ideias)
        #expect(tabs.boardFocusRequest == focusRequests + 1)

        model.open(viagemIndex, in: tabs)

        #expect(tabs.selected?.boardID == viagem, "o segundo mural abre numa aba nova e fica selecionado")
        #expect(tabs.tabs.count == 2)
        #expect(model.lastDestination == viagem)

        model.open(model.entries.count, in: tabs)
        #expect(tabs.tabs.count == 2, "um índice fora da lista não abre nada")

        await tabs.closeAll()
        await workspace.finish()
    }

    // MARK: Colar

    @Test("Texto com .ask: ao carregar só há a opção de ler; o colar lê, a pessoa confirma e o post-it entra no mural do centro")
    func askedTextIsReadWhenPastingThenDeliveredAsSticky() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Compras"])
        let compras = try workspace.boardID("Compras")
        let pasteboard = workspace.makePasteboard()
        pasteboard.setString("Comprar pão", forType: .string)
        let model = workspace.makeModel(activeBoard: compras, reader: workspace.makeReader(pasteboard, .ask))

        await model.load()

        #expect(model.clipboard == .available(.text(nil)))
        #expect(model.clipboardContent == nil, "com .ask abrir só olha os tipos")
        #expect(model.options.map(\.action) == [.read])
        #expect(model.canPaste)

        // O primeiro colar só lê: com mais de um tipo de cartão possível, a pessoa escolhe e confirma com outro Return.
        #expect(!model.readForPaste())
        #expect(model.clipboard == .available(.text("Comprar pão")))
        #expect(model.clipboardContent != nil)
        #expect(model.options.map(\.id) == ["text-sticky", "text-text"])
        #expect(model.options[model.selectedOption].action == .text(.sticky), "o post-it é o sugerido para um texto curto")
        #expect(model.pasteStatus == .idle)

        #expect(await model.paste())

        #expect(model.pasteStatus == .pasted("Colado em Compras"))
        #expect(model.lastDestination == compras)
        let entry = try #require(model.selectedEntry)
        #expect(entry.manifest.id == compras)
        let board = try #require(try await workspace.library.readBoard(entry.route))
        let sticky = try #require(board.items.first { $0.kind == .sticky })
        #expect(sticky.text == "Comprar pão")
        #expect(sticky.parentID == nil, "o cartão entra na raiz do mural")
        #expect(board.items.count == 1)

        await workspace.finish()
    }

    @Test("Imagem com .alwaysAllow: já vem lida ao abrir, o colar não pede confirmação, e um segundo pedido não cola de novo")
    func allowedImageIsReadOnOpenAndDeliveredOnce() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Fotos"])
        let fotos = try workspace.boardID("Fotos")
        let pasteboard = workspace.makePasteboard()
        pasteboard.setData(try TestImage.png(width: 64, height: 48), forType: .png)
        let model = workspace.makeModel(activeBoard: fotos, reader: workspace.makeReader(pasteboard, .alwaysAllow))

        await model.load()

        #expect(model.clipboard == .available(.image))
        #expect(model.clipboardContent != nil, "sem aviso do sistema, abrir já lê")
        #expect(model.options.map(\.id) == ["asRead"])
        #expect(model.selectedOption == 0)

        #expect(model.readForPaste())
        #expect(await model.paste())

        #expect(model.pasteStatus == .pasted("Colado em Fotos"))
        #expect(model.lastDestination == fotos)
        let entry = try #require(model.selectedEntry)
        let board = try #require(try await workspace.library.readBoard(entry.route))
        let photo = try #require(board.items.first { $0.kind == .image })
        #expect(photo.title == "Imagem colada")
        #expect(board.items.count == 1)

        // Um Return a mais enquanto o painel mostra "Colado em …" não pode criar um cartão repetido.
        #expect(!model.readForPaste())
        let again = await model.paste()
        #expect(!again)
        let afterSecondRequest = try #require(try await workspace.library.readBoard(entry.route))
        #expect(afterSecondRequest.items.count == 1)

        await workspace.finish()
    }

    @Test("Área de transferência vazia: não há como colar, e colar diz que não há nada")
    func emptyClipboardCannotBePasted() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Vazio"])
        let vazio = try workspace.boardID("Vazio")
        let model = workspace.makeModel(activeBoard: vazio, reader: workspace.makeReader(workspace.makePasteboard(), .ask))

        await model.load()

        #expect(model.clipboard == .nothing)
        #expect(model.options.isEmpty)
        #expect(!model.canPaste)
        #expect(!model.readForPaste())
        #expect(model.pasteStatus == .failed("Não há nada para colar."))
        let entry = try #require(model.selectedEntry)
        #expect(try await workspace.library.readBoard(entry.route)?.items.isEmpty == true, "nada entrou no mural")
        #expect(model.lastDestination == nil, "sem colar, o destino não é lembrado")

        await workspace.finish()
    }

    @Test("Privado nunca é lido; leitura negada não esconde o colar, e sem nada lido o motivo aparece")
    func protectedAndDeniedClipboardsExplainThemselves() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Quadro"])
        let quadro = try workspace.boardID("Quadro")

        let secret = workspace.makePasteboard()
        let concealed = NSPasteboardItem()
        concealed.setString("senha-123", forType: .string)
        concealed.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        secret.writeObjects([concealed])
        let guarded = workspace.makeModel(activeBoard: quadro, reader: workspace.makeReader(secret, .alwaysAllow))
        await guarded.load()
        #expect(guarded.clipboard == .protected)
        #expect(guarded.clipboardContent == nil)
        #expect(!guarded.canPaste)
        #expect(!guarded.readForPaste())
        #expect(guarded.pasteStatus == .failed("O que está copiado é privado (como uma senha) e o Mural não lê."))

        let denied = workspace.makePasteboard()
        denied.setString("Olá", forType: .string)
        let withText = workspace.makeModel(activeBoard: quadro, reader: workspace.makeReader(denied, .alwaysDeny))
        await withText.load()
        #expect(withText.clipboard == .deniedBySystem)
        #expect(withText.options.isEmpty)
        #expect(withText.canPaste, "o ⌘V da pessoa ainda lê")
        #expect(!withText.readForPaste(), "texto lido agora: a pessoa escolhe o tipo")
        #expect(withText.clipboard == .available(.text("Olá")))
        #expect(!withText.options.isEmpty)

        let blocked = workspace.makeModel(
            activeBoard: quadro, reader: workspace.makeReader(workspace.makePasteboard(), .alwaysDeny))
        await blocked.load()
        #expect(blocked.clipboard == .deniedBySystem)
        #expect(!blocked.readForPaste())
        #expect(blocked.pasteStatus == .failed("O macOS não deixou o Mural ler o que foi copiado."))

        await workspace.finish()
    }

    @Test("As opções param nas pontas, a sugerida começa escolhida e é a opção escolhida que define o tipo do cartão")
    func optionsAreClampedAndTheChosenOneDefinesTheCard() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Listas"])
        let listas = try workspace.boardID("Listas")
        let pasteboard = workspace.makePasteboard()
        pasteboard.setString("- ovos\n- leite", forType: .string)
        let model = workspace.makeModel(activeBoard: listas, reader: workspace.makeReader(pasteboard, .alwaysAllow))

        // Antes de carregar não há opções: escolher e andar não fazem nada.
        model.moveOption(by: 1)
        model.selectOption(2)
        #expect(model.selectedOption == 0)

        await model.load()
        #expect(model.options.map(\.id) == ["text-sticky", "text-text", "text-checklist"])
        #expect(model.selectedOption == 2, "um texto com marcadores sugere a lista")

        model.moveOption(by: 1)
        #expect(model.selectedOption == 2, "depois da última não há nada, e não dá a volta")
        model.moveOption(by: -1)
        #expect(model.selectedOption == 1)
        model.moveOption(by: -9)
        #expect(model.selectedOption == 0, "antes da primeira também não")
        model.selectOption(99)
        #expect(model.selectedOption == 2)
        model.selectOption(-5)
        #expect(model.selectedOption == 0)

        // Texto já lido ao abrir: o colar vai direto, e o cartão é o da opção escolhida, não o da sugerida.
        model.selectOption(1)
        #expect(model.readForPaste())
        #expect(await model.paste())
        let entry = try #require(model.selectedEntry)
        let board = try #require(try await workspace.library.readBoard(entry.route))
        #expect(board.items.map(\.kind) == [.text])

        await workspace.finish()
    }

    @Test("Os nomes do tipo, as prévias e os títulos das opções")
    func descriptionsNameThePreviewAndTitleTheOptions() throws {
        let kinds: [ClipboardKind] = [
            .text(nil), .links(count: 0), .links(count: 3), .image, .pdf, .files(count: 2), .music(count: 0), .music(count: 4),
        ]
        #expect(
            kinds.map(PasteDescription.name(for:)) == ["Texto", "Link", "3 links", "Imagem", "PDF", "2 arquivos", "Música", "4 músicas"])

        func title(_ kind: ClipboardKind) throws -> String {
            let option = try #require(PasteOptions.options(for: kind).first)
            return PasteDescription.title(of: option, clipboard: kind)
        }
        #expect(try title(.text(nil)) == "Colar texto", "antes de ler, o tipo do texto ainda não é conhecido")
        #expect(try title(.text("Comprar pão")) == "Colar como Sticker")
        #expect(try title(.links(count: 3)) == "Colar 3 links")
        #expect(try title(.image) == "Colar imagem")
        #expect(try title(.pdf) == "Colar PDF")
        #expect(try title(.files(count: 2)) == "Colar 2 arquivos")
        #expect(try title(.music(count: 1)) == "Colar música")
        #expect(PasteDescription.symbol(of: try #require(PasteOptions.options(for: .files(count: 2)).first)) == "clipboard")
        #expect(PasteDescription.symbol(of: try #require(PasteOptions.options(for: .image).first)) == "photo")

        let editOptions = PasteOptions.options(forEdited: .image)
        let edit = try #require(editOptions.first { $0.action == .edit })
        let discard = try #require(editOptions.first { $0.action == .discardEdit })
        #expect(PasteDescription.title(of: edit, clipboard: .image) == "Editar antes de colar")
        #expect(PasteDescription.title(of: discard, clipboard: .image) == "Descartar a edição")
        #expect(PasteDescription.symbol(of: edit) == "square.and.pencil")
        #expect(PasteDescription.symbol(of: discard) == "xmark.circle")

        let long = String(repeating: "a", count: 80)
        #expect(PasteDescription.preview(of: .pasted(.text("\n  Primeira linha \nSegunda"))) == "Primeira linha")
        #expect(PasteDescription.preview(of: .pasted(.text(long))) == String(repeating: "a", count: 60) + "…")
        let link = LinkDraft(url: try #require(URL(string: "https://www.Example.com/artigo")))
        #expect(PasteDescription.preview(of: .pasted(.links([link]))) == "example.com")
        #expect(PasteDescription.preview(of: .pasted(.files([URL(fileURLWithPath: "/tmp/relatório.pdf")]))) == "relatório.pdf")
        let album = MusicSnapshot(kind: .album, catalogID: "1441164426", title: "Abbey Road")
        #expect(PasteDescription.preview(of: .music([MusicDraft(snapshot: album)])) == "Abbey Road")
        #expect(PasteDescription.preview(of: nil) == nil)
        #expect(PasteDescription.preview(of: .pasted(.data(Data(), fileExtension: "png", kind: .image, title: "Imagem colada"))) == nil)
    }

    // MARK: Etapas e formatação

    @Test("O painel abre na vitrine; Tab mostra as maneiras de colar e depois a formatação, e volta à vitrine")
    func tabWalksThroughTheStagesAndWrapsAround() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Notas"])
        let pasteboard = workspace.makePasteboard()
        pasteboard.setString("Comprar pão", forType: .string)
        let model = workspace.makeModel(reader: workspace.makeReader(pasteboard, .alwaysAllow))

        await model.load()

        #expect(model.stage == .boards, "nenhuma maneira de colar fica escolhida ao abrir")
        #expect(model.stages == [.boards, .paste, .format])
        #expect(model.advanceStage())
        #expect(model.stage == .paste)
        #expect(model.advanceStage())
        #expect(model.stage == .format)
        #expect(model.advanceStage())
        #expect(model.stage == .boards, "depois da última etapa, o Tab volta à vitrine")

        await workspace.finish()
    }

    @Test("⇧Tab volta uma etapa e para na vitrine; Esc volta direto à vitrine")
    func shiftTabAndEscapeGoBack() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Notas"])
        let pasteboard = workspace.makePasteboard()
        pasteboard.setString("Comprar pão", forType: .string)
        let model = workspace.makeModel(reader: workspace.makeReader(pasteboard, .alwaysAllow))
        await model.load()

        #expect(!model.retreatStage(), "na vitrine não há para onde voltar")
        #expect(!model.returnToBoards(), "na vitrine o Esc fecha o painel")
        model.advanceStage()
        model.advanceStage()
        #expect(model.retreatStage())
        #expect(model.stage == .paste)
        model.advanceStage()
        #expect(model.returnToBoards())
        #expect(model.stage == .boards)

        await workspace.finish()
    }

    @Test("Sem texto não há formatação, e sem nada para colar a vitrine é a única etapa")
    func stagesDependOnTheClipboard() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Fotos"])
        let image = workspace.makePasteboard()
        image.setData(try TestImage.png(width: 8, height: 8), forType: .png)
        let withImage = workspace.makeModel(reader: workspace.makeReader(image, .alwaysAllow))
        await withImage.load()
        #expect(withImage.formats.isEmpty)
        #expect(withImage.stages == [.boards, .paste])
        withImage.advanceStage()
        #expect(withImage.advanceStage())
        #expect(withImage.stage == .boards, "sem formatação, o segundo Tab já volta à vitrine")

        let empty = workspace.makeModel(reader: workspace.makeReader(workspace.makePasteboard(), .alwaysAllow))
        await empty.load()
        #expect(empty.stages == [.boards])
        #expect(!empty.advanceStage())
        #expect(empty.stage == .boards)

        await workspace.finish()
    }

    @Test("A formatação escolhida entra no cartão, e as setas param nas pontas da lista")
    func chosenFormatShapesThePastedCard() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Compras"])
        let compras = try workspace.boardID("Compras")
        let pasteboard = workspace.makePasteboard()
        pasteboard.setString("ovos\nleite", forType: .string)
        let model = workspace.makeModel(activeBoard: compras, reader: workspace.makeReader(pasteboard, .alwaysAllow))
        await model.load()

        #expect(model.formats == PasteTextFormat.allCases)
        #expect(model.selectedFormat == .original)
        model.moveFormat(by: -1)
        #expect(model.selectedFormat == .original, "antes da primeira não há nada")
        model.moveFormat(by: 99)
        #expect(model.selectedFormat == .uppercase, "nem depois da última")
        model.selectFormat(.taskList)
        #expect(model.formattedText(.taskList) == "- [ ] ovos\n- [ ] leite")

        // O texto vira uma nota (card de texto), com a formatação escolhida.
        let note = try #require(model.options.firstIndex { $0.action == .text(.text) })
        model.selectOption(note)
        #expect(model.readForPaste())
        #expect(await model.paste())
        let entry = try #require(model.selectedEntry)
        let board = try #require(try await workspace.library.readBoard(entry.route))
        let card = try #require(board.items.first)
        #expect(card.kind == .text)
        #expect(card.text == "- [ ] ovos\n- [ ] leite")

        await workspace.finish()
    }

    @Test("Com .ask o texto ainda não foi lido: a formatação aceita a escolha, e o colar lê e passa às maneiras de colar")
    func unreadTextKeepsTheFormatAndAsksForTheCardKind() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Ideias"])
        let pasteboard = workspace.makePasteboard()
        pasteboard.setString("  Ideia   solta  ", forType: .string)
        let model = workspace.makeModel(reader: workspace.makeReader(pasteboard, .ask))
        await model.load()

        #expect(model.clipboardContent == nil)
        #expect(model.stages == [.boards, .paste, .format])
        #expect(model.formattedText(.tidy) == nil, "sem ler, não há prévia")
        model.advanceStage()
        model.advanceStage()
        model.selectFormat(.tidy)

        #expect(!model.readForPaste(), "com o texto lido, a pessoa escolhe o tipo de cartão")
        #expect(model.stage == .paste)
        #expect(model.selectedFormat == .tidy, "a formatação escolhida antes de ler continua")
        #expect(model.formattedText(.tidy) == "Ideia solta")

        #expect(await model.paste())
        let entry = try #require(model.selectedEntry)
        let board = try #require(try await workspace.library.readBoard(entry.route))
        #expect(board.items.first?.text == "Ideia solta")

        await workspace.finish()
    }
    // MARK: Editar antes de colar

    /// Abre o painel sobre um texto ainda não lido (`.ask`), escolhe "Editar" e abre o editor.
    private func startTextEdit(
        _ workspace: PanelWorkspace, board: BoardID, text: String, editor: PasteEditor
    ) async throws -> (model: MenuBarPanelModel, pasteboard: NSPasteboard) {
        let pasteboard = workspace.makePasteboard()
        pasteboard.setString(text, forType: .string)
        let model = workspace.makeModel(
            activeBoard: board, reader: workspace.makeReader(pasteboard, .ask), editor: editor)
        await model.load()
        try selectOption("edit", in: model)
        #expect(model.readForPaste())
        #expect(await model.paste())
        return (model, pasteboard)
    }

    private func selectOption(_ id: String, in model: MenuBarPanelModel) throws {
        model.selectOption(try #require(model.options.firstIndex { $0.id == id }))
    }

    @Test("Texto ainda não lido oferece Editar; escolhê-la lê sem parar na escolha do cartão e abre o editor")
    func unreadTextOffersEditAndOpensTheEditor() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Compras"])
        let compras = try workspace.boardID("Compras")
        let launcher = FakeEditorLauncher()
        let editor = workspace.makeEditor(launcher: launcher)
        let pasteboard = workspace.makePasteboard()
        pasteboard.setString("Comprar pão", forType: .string)
        let model = workspace.makeModel(
            activeBoard: compras, reader: workspace.makeReader(pasteboard, .ask), editor: editor)
        await model.load()

        #expect(model.options.map(\.id) == ["read", "edit"])
        #expect(model.editorName == "Editor Teste")
        #expect(model.source == .clipboard)
        try selectOption("edit", in: model)
        #expect(model.stages == [.boards, .paste], "escolher Editar tira a formatação")

        #expect(model.readForPaste(), "com Editar escolhida, ler não para na escolha do tipo de cartão")
        #expect(model.options.map(\.id) == ["text-sticky", "text-text", "edit"])
        #expect(model.options[model.selectedOption].action == .edit)
        #expect(await model.paste())

        let pending = try #require(editor.pending)
        #expect(pending.boardID == compras)
        #expect(try String(contentsOf: pending.session.file, encoding: .utf8) == "Comprar pão")
        #expect(launcher.calls.count == 1)
        #expect(launcher.calls.first?.application == PanelWorkspace.editorApp.url)
        #expect(model.pasteStatus == .pasted("Editando com Editor Teste. Volte ao painel para colar."))
        #expect(model.lastDestination == nil, "o destino só é lembrado num colar de verdade")

        await workspace.finish()
    }

    @Test("O painel que abre de novo mostra a edição, mesmo com outra coisa copiada, e colar entrega o texto editado")
    func reopenedPanelShowsTheEditAndPastesIt() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Compras"])
        let compras = try workspace.boardID("Compras")
        let launcher = FakeEditorLauncher()
        launcher.editedText = "Comprar pão (editado)"
        let editor = workspace.makeEditor(launcher: launcher)
        let (_, pasteboard) = try await startTextEdit(workspace, board: compras, text: "Comprar pão", editor: editor)
        pasteboard.clearContents()
        pasteboard.setString("Outra coisa", forType: .string)

        let model = workspace.makeModel(
            activeBoard: compras, reader: workspace.makeReader(pasteboard, .alwaysAllow), editor: editor)
        await model.load()

        #expect(model.source == .edit)
        #expect(model.stage == .paste)
        #expect(model.editorName == "Editor Teste")
        #expect(model.pasteStatus == .idle)
        #expect(model.clipboard == .available(.text("Comprar pão (editado)")))
        #expect(model.options.map(\.id) == ["text-sticky", "text-text", "edit", "discardEdit"])

        #expect(model.readForPaste())
        #expect(await model.paste())

        #expect(model.pasteStatus == .pasted("Colado em Compras"))
        #expect(editor.pending == nil)
        let entry = try #require(model.selectedEntry)
        let board = try #require(try await workspace.library.readBoard(entry.route))
        #expect(board.items.first { $0.kind == .sticky }?.text == "Comprar pão (editado)")

        await workspace.finish()
    }

    @Test("Descartar a edição volta às opções da área de transferência, com Editar de novo")
    func discardReturnsToTheClipboard() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Compras"])
        let compras = try workspace.boardID("Compras")
        let editor = workspace.makeEditor(launcher: FakeEditorLauncher())
        let (_, pasteboard) = try await startTextEdit(workspace, board: compras, text: "Comprar pão", editor: editor)
        let model = workspace.makeModel(
            activeBoard: compras, reader: workspace.makeReader(pasteboard, .ask), editor: editor)
        await model.load()
        try selectOption("discardEdit", in: model)

        #expect(model.readForPaste())
        #expect(await model.paste() == false, "descartar não fecha o painel")

        #expect(editor.pending == nil)
        #expect(model.source == .clipboard)
        #expect(model.options.map(\.id) == ["read", "edit"])
        #expect(model.pasteStatus == .idle)

        await workspace.finish()
    }

    @Test("O ⌘V não descarta: com Descartar escolhida volta à opção sugerida")
    func pasteCommandNeverDiscards() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Compras"])
        let compras = try workspace.boardID("Compras")
        let editor = workspace.makeEditor(launcher: FakeEditorLauncher())
        let (_, pasteboard) = try await startTextEdit(workspace, board: compras, text: "Comprar pão", editor: editor)
        let model = workspace.makeModel(
            activeBoard: compras, reader: workspace.makeReader(pasteboard, .ask), editor: editor)
        await model.load()
        try selectOption("discardEdit", in: model)

        model.preferPasteOverDiscard()

        #expect(model.options[model.selectedOption].action == .text(.sticky))

        await workspace.finish()
    }

    @Test("Enquanto o editor abre, o estado é trabalhando e outro Return não faz nada")
    func returnWhileWorkingDoesNothing() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Compras"])
        let compras = try workspace.boardID("Compras")
        let launcher = FakeEditorLauncher()
        launcher.delay = .milliseconds(400)
        let editor = workspace.makeEditor(launcher: launcher)
        let pasteboard = workspace.makePasteboard()
        pasteboard.setString("Comprar pão", forType: .string)
        let model = workspace.makeModel(
            activeBoard: compras, reader: workspace.makeReader(pasteboard, .ask), editor: editor)
        await model.load()
        try selectOption("edit", in: model)
        #expect(model.readForPaste())
        let task = Task { await model.paste() }
        for _ in 0..<100 where launcher.calls.isEmpty { try await Task.sleep(for: .milliseconds(20)) }

        #expect(model.pasteStatus == .working("Abrindo com Editor Teste…"))
        #expect(!model.readForPaste())
        #expect(await model.paste() == false)
        #expect(await task.value)
        #expect(launcher.calls.count == 1)

        await workspace.finish()
    }

    @Test("Texto que vira links ao ser lido não abre o editor nem cola nada")
    func textThatBecomesLinksNeverEdits() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Compras"])
        let compras = try workspace.boardID("Compras")
        let launcher = FakeEditorLauncher()
        let editor = workspace.makeEditor(launcher: launcher)
        let pasteboard = workspace.makePasteboard()
        pasteboard.setString("Comprar pão", forType: .string)
        let model = workspace.makeModel(
            activeBoard: compras, reader: workspace.makeReader(pasteboard, .ask), editor: editor)
        await model.load()
        try selectOption("edit", in: model)
        pasteboard.clearContents()
        pasteboard.setString("https://example.com/artigo", forType: .string)

        #expect(!model.readForPaste())

        #expect(model.stage == .paste)
        #expect(!model.options.contains { $0.action == .edit })
        #expect(editor.pending == nil)
        #expect(launcher.calls.isEmpty)
        let entry = try #require(model.selectedEntry)
        let board = try #require(try await workspace.library.readBoard(entry.route))
        #expect(board.items.isEmpty)

        await workspace.finish()
    }

    @Test("Falha ao abrir o editor: aparece e é consumida; com a tarefa cancelada, fica para a próxima abertura")
    func launcherFailure() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Compras"])
        let compras = try workspace.boardID("Compras")
        let launcher = FakeEditorLauncher()
        launcher.failure = FakeEditorLauncher.Failure()
        let editor = workspace.makeEditor(launcher: launcher)
        let pasteboard = workspace.makePasteboard()
        pasteboard.setString("Comprar pão", forType: .string)
        func openedModel() async throws -> MenuBarPanelModel {
            let model = workspace.makeModel(
                activeBoard: compras, reader: workspace.makeReader(pasteboard, .ask), editor: editor)
            await model.load()
            try selectOption("edit", in: model)
            #expect(model.readForPaste())
            return model
        }

        let direct = try await openedModel()
        #expect(await direct.paste() == false)
        guard case .failed(let message) = direct.pasteStatus else {
            Issue.record("deveria falhar")
            return
        }
        #expect(message.contains("Editor Teste"))
        #expect(editor.pending == nil)
        #expect(editor.takeLastFailure() == nil, "uma falha vista não aparece de novo")

        let cancelled = try await openedModel()
        let task = Task { await cancelled.paste() }
        task.cancel()
        #expect(await task.value == false)
        let next = workspace.makeModel(
            activeBoard: compras, reader: workspace.makeReader(pasteboard, .ask), editor: editor)
        await next.load()
        guard case .failed(let later) = next.pasteStatus else {
            Issue.record("a falha deveria aparecer na próxima abertura")
            return
        }
        #expect(later.contains("Editor Teste"))
        let third = workspace.makeModel(
            activeBoard: compras, reader: workspace.makeReader(pasteboard, .ask), editor: editor)
        await third.load()
        #expect(third.pasteStatus == .idle, "e só aparece uma vez")

        await workspace.finish()
    }

    @Test("Imagem editada: abre, o painel novo lê o PNG de volta e cola como imagem; a pasta some")
    func imageEditEndToEnd() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Fotos"])
        let fotos = try workspace.boardID("Fotos")
        let editor = workspace.makeEditor(launcher: FakeEditorLauncher())
        let pasteboard = workspace.makePasteboard()
        pasteboard.setData(try TestImage.png(width: 64, height: 48), forType: .png)
        let first = workspace.makeModel(
            activeBoard: fotos, reader: workspace.makeReader(pasteboard, .alwaysAllow), editor: editor)
        await first.load()
        #expect(first.options.map(\.id) == ["asRead", "edit"])
        try selectOption("edit", in: first)
        #expect(first.readForPaste())
        #expect(await first.paste())
        let pending = try #require(editor.pending)
        #expect(pending.session.kind == .image)
        #expect(pending.session.file.pathExtension == "png")

        let second = workspace.makeModel(
            activeBoard: fotos, reader: workspace.makeReader(pasteboard, .alwaysAllow), editor: editor)
        await second.load()
        #expect(second.source == .edit)
        #expect(second.options.map(\.id) == ["asRead", "edit", "discardEdit"])
        #expect(second.readForPaste())
        #expect(await second.paste())

        #expect(second.pasteStatus == .pasted("Colado em Fotos"))
        #expect(editor.pending == nil)
        #expect(!FileManager.default.fileExists(atPath: pending.session.folder.path))
        let entry = try #require(second.selectedEntry)
        let board = try #require(try await workspace.library.readBoard(entry.route))
        #expect(board.items.first { $0.kind == .image } != nil)

        await workspace.finish()
    }

    @Test("A formatação só existe quando a opção escolhida cola texto")
    func formatStageFollowsTheSelectedOption() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Compras"])
        let compras = try workspace.boardID("Compras")
        let editor = workspace.makeEditor(launcher: FakeEditorLauncher())
        let pasteboard = workspace.makePasteboard()
        pasteboard.setString("Comprar pão", forType: .string)
        let model = workspace.makeModel(
            activeBoard: compras, reader: workspace.makeReader(pasteboard, .ask), editor: editor)
        await model.load()
        #expect(model.stages == [.boards, .paste, .format])
        model.advanceStage()
        model.advanceStage()
        #expect(model.stage == .format)

        try selectOption("edit", in: model)

        #expect(model.stages == [.boards, .paste])
        #expect(model.stage == .paste, "a etapa que sumiu dá lugar à anterior")
        try selectOption("read", in: model)
        #expect(model.stages == [.boards, .paste, .format])

        await workspace.finish()
    }

    @Test("Com uma edição pendente, o mural do centro é o dela, mesmo com outro como último destino")
    func initialBoardIsThePendingEditBoard() async throws {
        let workspace = try await PanelWorkspace.make(boards: ["Ideias", "Compras"])
        let ideias = try workspace.boardID("Ideias")
        let compras = try workspace.boardID("Compras")
        let editor = workspace.makeEditor(launcher: FakeEditorLauncher())
        _ = try await startTextEdit(workspace, board: compras, text: "Comprar pão", editor: editor)
        let model = workspace.makeModel(activeBoard: ideias, editor: editor)
        model.rememberDestination(ideias)

        await model.load()

        #expect(model.selectedEntry?.manifest.id == compras)

        await workspace.finish()
    }

}
