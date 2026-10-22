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
        // Mural excluído nos testes é apagado, não vai para o Lixo de quem roda os testes.
        let library = BoardLibrary(
            rootDirectory: directory, discardPackage: { url in try FileManager.default.removeItem(at: url) })
        return (library, directory)
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
    @Test("Arrastar uma aba a põe na posição nova, para os dois lados; fora da faixa, nada muda")
    func movingTabsReorders() async throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (tabs, _) = makeTabs(library)
        let a = try #require(tabs.open(try await library.createNamedBoard("A"), title: "A"))
        let b = try #require(tabs.open(try await library.createNamedBoard("B"), title: "B"))
        let c = try #require(tabs.open(try await library.createNamedBoard("C"), title: "C"))

        tabs.moveTab(a.id, toIndex: 2)
        #expect(tabs.tabs.map(\.id) == [b.id, c.id, a.id])
        tabs.moveTab(a.id, toIndex: 0)
        #expect(tabs.tabs.map(\.id) == [a.id, b.id, c.id])
        tabs.moveTab(b.id, toIndex: 1)
        tabs.moveTab(b.id, toIndex: 7)
        #expect(tabs.tabs.map(\.id) == [a.id, b.id, c.id], "no mesmo lugar ou fora da faixa, nada muda")
        #expect(tabs.selectedID == c.id, "mudar a ordem não troca a aba ativa")
        #expect(tabs.snapshot.entries.map(\.title) == ["A", "B", "C"], "a ordem nova vale para a restauração")
        await tabs.closeAll()
    }

    // MARK: Excluir mural

    @Test("Excluir o mural de uma aba fecha a aba, solta a sessão e tira o mural da lista; a janela fica")
    func deletingOpenBoardClosesItsTab() async throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (tabs, closes) = makeTabs(library)
        var cleared: [BoardID] = []
        tabs.removeBoardCaches = { cleared.append($0) }
        let doomedRoute = try await library.createNamedBoard("Excluir")
        let keptRoute = try await library.createNamedBoard("Manter")
        let kept = try #require(tabs.open(keptRoute))
        let doomed = try #require(tabs.open(doomedRoute))
        await waitUntil("o mural carregar") { doomed.session.model != nil }

        try await tabs.deleteBoard(doomedRoute)

        #expect(tabs.tabs.map(\.id) == [kept.id])
        #expect(tabs.selectedID == kept.id)
        #expect(await tabs.registry.session(for: doomed.boardID) == nil, "nenhuma sessão viva recria o pacote")
        #expect(try await library.listSaved().map(\.manifest.name) == ["Manter"])
        #expect(cleared == [doomed.boardID], "as prévias de link do mural saem junto")

        try await tabs.deleteBoard(keptRoute)
        #expect(tabs.tabs.isEmpty)
        #expect(closes.count == 0, "excluir a última aba não fecha a janela")
        #expect(tabs.isSidebarVisible)
    }

    @Test("Excluir um mural que não está aberto não mexe nas abas")
    func deletingClosedBoardKeepsTabs() async throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (tabs, _) = makeTabs(library)
        tabs.removeBoardCaches = { _ in }
        let open = try #require(tabs.open(try await library.createNamedBoard("Aberto")))
        let closedRoute = try await library.createNamedBoard("Fechado")

        try await tabs.deleteBoard(closedRoute)

        #expect(tabs.tabs.map(\.id) == [open.id])
        #expect(try await library.listSaved().map(\.manifest.name) == ["Aberto"])
        await tabs.closeAll()
    }

    @Test("Pedir para excluir guarda o pedido e abre a janela; Arquivo › Excluir usa a aba ativa")
    func deletionRequestsWaitForConfirmation() async throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (tabs, _) = makeTabs(library)
        var opened = 0
        tabs.openMainWindow = { opened += 1 }
        let route = try await library.createNamedBoard("Pedido")
        _ = tabs.open(route, title: "Pedido")

        tabs.requestDeleteSelected()
        #expect(tabs.deletionRequest == BoardDeletionRequest(route: route, name: "Pedido"))
        #expect(opened == 1)
        tabs.requestDelete(.library, name: "Murais")
        #expect(tabs.deletionRequest?.route == route, "a biblioteca não se exclui")
        #expect(try await library.listSaved().count == 1, "nada é excluído antes da confirmação")
        await tabs.closeAll()
    }

    @Test("Excluir o rascunho de exemplo o descarta e desliga Retomar rascunho")
    func deletingDraftDiscardsIt() async throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (tabs, _) = makeTabs(library)
        tabs.removeBoardCaches = { _ in }
        let state = try await library.bootstrap()
        await tabs.resumeDraft()
        #expect(tabs.resumeDraftAvailable)

        try await tabs.deleteBoard(.welcomeDraft(state.stableWelcomeID))

        #expect(tabs.tabs.isEmpty)
        #expect(!tabs.resumeDraftAvailable)
        #expect(try await library.lifecycleState()?.lifecycle == .discarded)
    }

    @Test("Dentro do app, mover para o Lixo funciona e diz onde o item foi parar")
    func trashWorksInsideTheSandbox() throws {
        let item = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralLixo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: item, withIntermediateDirectories: true)
        var resulting: NSURL?
        try FileManager.default.trashItem(at: item, resultingItemURL: &resulting)
        let trashed = try #require(resulting as URL?)
        defer { try? FileManager.default.removeItem(at: trashed) }
        #expect(!FileManager.default.fileExists(atPath: item.path))
        #expect(FileManager.default.fileExists(atPath: trashed.path))
    }
}

/// Conta os pedidos de fechar a janela.
@MainActor
private final class WindowCloses {
    var count = 0
}
