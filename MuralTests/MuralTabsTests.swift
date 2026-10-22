import Foundation
import MuralKit
import Testing

@testable import Mural

/// As abas da janela: um mural em uma aba só, a vizinha certa ao fechar, nada de troca com uma folha
/// aberta e a restauração entre aberturas do app.
@Suite("Abas da janela")
@MainActor
struct MuralTabsTests {
    private func makeLibrary() throws -> (BoardLibrary, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralTabs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (BoardLibrary(rootDirectory: directory), directory)
    }

    private func makeTabs(_ library: BoardLibrary) -> (MuralTabs, WindowCloses) {
        let tabs = MuralTabs(registry: BoardSessionRegistry(library: library))
        let closes = WindowCloses()
        tabs.closeWindow = { closes.count += 1 }
        return (tabs, closes)
    }

    @Test("Abrir cria a aba à direita da ativa e a seleciona; abrir de novo só volta para ela")
    func openInsertsAfterSelectedAndDeduplicates() async throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (tabs, _) = makeTabs(library)
        let a = try await library.createNamedBoard("A")
        let b = try await library.createNamedBoard("B")
        let c = try await library.createNamedBoard("C")

        let tabA = try #require(tabs.open(a, title: "A"))
        let tabB = try #require(tabs.open(b, title: "B"))
        tabs.select(tabA.id)
        let tabC = try #require(tabs.open(c, title: "C"))
        #expect(tabs.tabs.map(\.id) == [tabA.id, tabC.id, tabB.id], "a nova entra logo depois da ativa")
        #expect(tabs.selectedID == tabC.id)

        #expect(tabs.open(b)?.id == tabB.id, "o mesmo mural não abre duas vezes")
        #expect(tabs.tabs.count == 3)
        #expect(tabs.selectedID == tabB.id)
        #expect(tabs.open(.library) == nil, "a biblioteca não é uma aba")
        await tabs.closeAll()
    }

    @Test("Fechar a ativa passa para a vizinha da direita, senão a da esquerda; a última fecha a janela")
    func closeSelectsNeighborAndLastClosesWindow() async throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (tabs, closes) = makeTabs(library)
        let tabA = try #require(tabs.open(try await library.createNamedBoard("A")))
        let tabB = try #require(tabs.open(try await library.createNamedBoard("B")))
        let tabC = try #require(tabs.open(try await library.createNamedBoard("C")))

        tabs.select(tabB.id)
        tabs.close(tabB.id)
        #expect(tabs.selectedID == tabC.id, "a vizinha da direita assume")
        tabs.close(tabC.id)
        #expect(tabs.selectedID == tabA.id, "sem vizinha à direita, a da esquerda")
        #expect(closes.count == 0)
        tabs.close(tabA.id)
        #expect(tabs.tabs.isEmpty)
        #expect(closes.count == 1, "sem abas, a janela fecha")
        #expect(tabs.isSidebarVisible, "a janela reaberta mostra os murais")
    }

    @Test("Fechar uma aba grava o mural dela e o solta no registro")
    func closingTabFlushesAndReleases() async throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (tabs, _) = makeTabs(library)
        let route = try await library.createNamedBoard("Gravar")
        let tab = try #require(tabs.open(route))
        await waitUntil("o mural carregar") { tab.session.model != nil }
        let item = try #require(tab.session.model?.importText("fechado pela aba"))
        tab.session.captureBoardIfNeeded()

        tabs.close(tab.id)
        await waitUntil("a sessão ser solta") { await tabs.registry.ownerCount(for: tab.boardID) == 0 }
        let reopened = BoardWindowSession(route: route, registry: tabs.registry)
        await reopened.load()
        #expect(reopened.model?.item(id: item.id) != nil)
        await reopened.handleWindowWillClose()
    }

    @Test("Com uma folha aberta, a troca e o fechamento da aba ativa são recusados")
    func sheetBlocksSwitchingAndClosingSelected() async throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (tabs, _) = makeTabs(library)
        let tabA = try #require(tabs.open(try await library.createNamedBoard("A")))
        let tabB = try #require(tabs.open(try await library.createNamedBoard("B")))

        tabs.isShowingSheet = { true }
        #expect(!tabs.select(tabA.id))
        tabs.close(tabB.id)
        #expect(tabs.selectedID == tabB.id)
        #expect(tabs.tabs.count == 2)
        tabs.close(tabA.id)
        #expect(tabs.tabs.map(\.id) == [tabB.id], "uma aba de fundo fecha mesmo com a folha")
        tabs.isShowingSheet = { false }
        await tabs.closeAll()
    }

    @Test("Trocar de aba pausa a que sai e retoma a que entra, sem recarregar")
    func switchingSuspendsAndResumes() async throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (tabs, _) = makeTabs(library)
        let tabA = try #require(tabs.open(try await library.createNamedBoard("A")))
        await waitUntil("A carregar") { tabA.session.model != nil }
        let modelA = tabA.session.model
        let tabB = try #require(tabs.open(try await library.createNamedBoard("B")))
        #expect(tabA.session.restorationPhase == .loading, "a aba de fundo não grava posição")

        let generation = tabA.session.presentationGeneration
        tabs.select(tabA.id)
        #expect(tabA.session.model === modelA, "voltar não relê o disco")
        #expect(tabA.session.presentationGeneration == generation &+ 1)
        #expect(tabA.session.restorationPhase == .awaitingLayout)
        await waitUntil("B carregar") { tabB.session.model != nil || tabB.session.error != nil }
        await tabs.closeAll()
    }

    @Test("Rascunho promovido troca a rota na mesma posição e continua ativo")
    func replaceKeepsPosition() async throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (tabs, _) = makeTabs(library)
        let tabA = try #require(tabs.open(try await library.createNamedBoard("A")))
        _ = tabs.open(try await library.createNamedBoard("B"))
        tabs.select(tabA.id)
        let promoted = try await library.createNamedBoard("A promovido")

        tabs.replace(tabA.id, with: promoted)
        #expect(tabs.tabs.first?.route == promoted)
        #expect(tabs.selected?.route == promoted)
        #expect(tabs.tabs.count == 2)
        await tabs.closeAll()
    }

    @Test("Restauração: mural repetido e biblioteca ficam de fora; só a aba ativa carrega")
    func restoreSkipsInvalidAndLoadsOnlySelected() async throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (tabs, _) = makeTabs(library)
        let a = try await library.createNamedBoard("A")
        let b = try await library.createNamedBoard("B")
        let snapshot = MuralTabsSnapshot(
            entries: [
                .init(route: a, title: "A"), .init(route: a, title: "A"), .init(route: .library, title: "Murais"),
                .init(route: b, title: "B"),
            ],
            selectedIndex: 3)
        #expect(MuralTabsSnapshot(storage: snapshot.storage) == snapshot)
        #expect(MuralTabsSnapshot(storage: "") == nil)

        tabs.restore(snapshot)
        #expect(tabs.tabs.map(\.route) == [a, b])
        #expect(tabs.selected?.route == b)
        #expect(tabs.tabs.map(\.title) == ["A", "B"], "o nome guardado aparece antes de carregar")
        await waitUntil("B carregar") { tabs.selected?.session.model != nil }
        #expect(tabs.tabs.first?.session.model == nil, "a aba de fundo só carrega quando escolhida")
        await tabs.closeAll()
    }

    @Test("Pedidos sem janela ficam guardados e abrem a janela")
    func requestsWaitForTheWindow() throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (tabs, _) = makeTabs(library)
        var opened = 0
        tabs.openMainWindow = { opened += 1 }

        tabs.requestNewBoard()
        #expect(tabs.request == .newBoard)
        tabs.requestOpenPackage()
        #expect(tabs.request == .openPackage)
        tabs.showAllMurals()
        #expect(tabs.isSidebarVisible)
        #expect(opened == 3)
    }

    @Test("Retomar o rascunho abre a aba dele só enquanto ele é rascunho")
    func resumeDraftOnlyWhileDraft() async throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (tabs, _) = makeTabs(library)
        let state = try await library.bootstrap()
        #expect(state.lifecycle == .draft)

        await tabs.resumeDraft()
        #expect(tabs.resumeDraftAvailable)
        #expect(tabs.selected?.route == .welcomeDraft(state.stableWelcomeID))
        await tabs.closeAll()

        _ = try await library.promoteWelcomeDraft(name: "Promovido")
        await tabs.refreshDraftAvailability()
        #expect(!tabs.resumeDraftAvailable)
        await tabs.resumeDraft()
        #expect(tabs.tabs.isEmpty)
    }
}

/// Conta os pedidos de fechar a janela.
@MainActor
private final class WindowCloses {
    var count = 0
}
