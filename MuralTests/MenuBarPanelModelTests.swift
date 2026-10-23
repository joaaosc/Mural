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
/// ele foi chamado a fazer, e em que ordem.
@MainActor
private final class PanelWorkspace {
    let directory: URL
    let library: BoardLibrary
    let preferences: UserDefaults
    private let suiteName: String
    private let ids: [String: BoardID]
    private var services: [BoardCoverService] = []
    /// Os murais de que o serviço começou a fazer a capa, na ordem em que começou.
    private(set) var coverOrder: [BoardID] = []

    var coversDirectory: URL {
        directory.appendingPathComponent("BoardCovers", isDirectory: true)
    }

    private init(directory: URL, library: BoardLibrary, preferences: UserDefaults, suiteName: String, ids: [String: BoardID]) {
        self.directory = directory
        self.library = library
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
        return PanelWorkspace(directory: directory, library: library, preferences: preferences, suiteName: suiteName, ids: ids)
    }

    func boardID(_ name: String) throws -> BoardID {
        try #require(ids[name], "O mural \(name) não foi criado")
    }

    /// Um modelo novo sobre a mesma biblioteca, as mesmas preferências e a mesma pasta de capas.
    func makeModel(activeBoard: BoardID? = nil, now: @escaping () -> Date = Date.init) -> MenuBarPanelModel {
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
        return MenuBarPanelModel(library: library, covers: covers, activeBoard: { activeBoard }, preferences: preferences, now: now)
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
}
