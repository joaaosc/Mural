import CoreGraphics
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

    @Test("Fechar uma aba avisa onBoardClosed com o mural dela; fechar uma aba que não existe não avisa")
    func closeReportsTheClosedBoard() async throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (tabs, _) = makeTabs(library)
        let tabA = try #require(tabs.open(try await library.createNamedBoard("A")))
        let tabB = try #require(tabs.open(try await library.createNamedBoard("B")))
        let closed = ClosedBoards()
        tabs.onBoardClosed = { closed.ids.append($0) }

        tabs.close(UUID())
        #expect(closed.ids.isEmpty, "sem aba, nada saiu")
        tabs.close(tabA.id)
        #expect(closed.ids == [tabA.boardID])
        tabs.close(tabB.id)
        #expect(closed.ids == [tabA.boardID, tabB.boardID], "a última aba também avisa, antes de a janela fechar")
    }

    @Test("Fechar todas as abas avisa onBoardClosed com o mural de cada uma")
    func closeAllReportsEveryBoard() async throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (tabs, _) = makeTabs(library)
        for name in ["A", "B", "C"] { _ = try #require(tabs.open(try await library.createNamedBoard(name))) }
        let open = tabs.tabs.map(\.boardID)
        #expect(open.count == 3)
        let closed = ClosedBoards()
        tabs.onBoardClosed = { closed.ids.append($0) }

        await tabs.closeAll()
        #expect(closed.ids == open, "um aviso por mural, na ordem das abas")
        #expect(tabs.tabs.isEmpty)

        await tabs.closeAll()
        #expect(closed.ids == open, "sem abas, não há mais o que avisar")
    }

    @Test("Promover o rascunho avisa onBoardClosed com o mural que saiu da aba, e não com o novo; rota que não é mural não avisa")
    func replaceReportsTheOldBoard() async throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (tabs, _) = makeTabs(library)
        let tabA = try #require(tabs.open(try await library.createNamedBoard("A")))
        _ = tabs.open(try await library.createNamedBoard("B"))
        let promoted = try await library.createNamedBoard("A promovido")
        let closed = ClosedBoards()
        tabs.onBoardClosed = { closed.ids.append($0) }

        tabs.replace(tabA.id, with: .library)
        #expect(closed.ids.isEmpty, "a biblioteca não é uma aba: nada mudou")
        tabs.replace(tabA.id, with: promoted)
        #expect(closed.ids == [tabA.boardID])
        #expect(tabs.tab(for: tabA.boardID) == nil)
        #expect(tabs.tabs.first?.route == promoted)
        tabs.onBoardClosed = nil
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

        await tabs.requestDeleteSelected()
        #expect(tabs.deletionRequest == BoardDeletionRequest(route: route, name: "Pedido"))
        #expect(opened == 1)
        await tabs.requestDelete(.library, name: "Murais")
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

    @Test("Confirmar a exclusão só deste Mac avisa onBoardDeletedByUser; deleteBoard direto e pedido com erro não avisam")
    func performingLocalDeletionReportsTheBoard() async throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (tabs, _) = makeTabs(library)
        tabs.removeBoardCaches = { _ in }
        let deleted = DeletedBoards()
        tabs.onBoardDeletedByUser = { deleted.ids.append($0) }
        let doomed = try await library.createNamedBoard("Excluir")
        let swept = try await library.createNamedBoard("Sincronização")
        guard case .saved(let doomedID) = doomed else {
            Issue.record("rota inesperada")
            return
        }

        try await tabs.deleteBoard(swept)
        #expect(deleted.ids.isEmpty, "a exclusão por outro caminho (como a sincronização) não é da pessoa")
        // Sem sincronização ligada, sair do mural recebido e tirar do iCloud recusam, e nada é avisado.
        await #expect(throws: CloudSyncControllerError.disabled) {
            try await tabs.perform(BoardDeletionRequest(route: doomed, name: "Excluir", kind: .leave))
        }
        await #expect(throws: CloudSyncControllerError.disabled) {
            try await tabs.perform(BoardDeletionRequest(route: doomed, name: "Excluir", kind: .removeFromICloud(participants: 0)))
        }
        await #expect(throws: CloudSyncControllerError.disabled) {
            try await tabs.perform(BoardDeletionRequest(route: doomed, name: "Excluir", kind: .everywhere(participants: 0)))
        }
        #expect(deleted.ids.isEmpty)

        try await tabs.perform(BoardDeletionRequest(route: doomed, name: "Excluir"))
        #expect(deleted.ids == [doomedID])
        #expect(try await library.listSaved().isEmpty)
    }

    @Test("libraryDidChange avisa onLibraryChanged e muda a revisão da lista")
    func libraryChangeIsReported() throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (tabs, _) = makeTabs(library)
        var calls = 0
        tabs.onLibraryChanged = { calls += 1 }
        let before = tabs.libraryRevision

        tabs.libraryDidChange()

        #expect(calls == 1)
        #expect(tabs.libraryRevision == before &+ 1)
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

    /// Abas cujas sessões e o próprio `MuralTabs` usam o mesmo tocador falso, com um cartão de música tocando.
    private func makePlayingTabs(
        _ library: BoardLibrary
    ) async throws -> (tabs: MuralTabs, playing: BoardTab, other: BoardRoute, playingRoute: BoardRoute, fake: FakeMusic) {
        let fake = FakeMusic(arguments: [])
        let playback = MusicPlayback(provider: fake)
        let registry = BoardSessionRegistry(library: library)
        let tabs = MuralTabs(registry: registry) {
            let session = BoardWindowSession(route: $0, registry: registry)
            session.musicPlayback = playback
            return session
        }
        tabs.musicPlayback = playback
        tabs.closeWindow = {}
        tabs.removeBoardCaches = { _ in }
        let playingRoute = try await library.createNamedBoard("Toca")
        let other = try await library.createNamedBoard("Outro")
        let tab = try #require(tabs.open(playingRoute, title: "Toca"))
        await waitUntil("o mural carregar") { tab.session.model != nil }
        let metrics = CanvasScrollMetrics(
            contentOffset: .zero, containerSize: CGSize(width: 900, height: 700), contentSize: CGSize(width: 3_400, height: 2_800))
        for _ in 0..<3 where tab.session.restorationPhase != .ready {
            tab.session.restoreCanvas(
                boardID: tab.session.boardID, generation: tab.session.presentationGeneration, metrics: metrics)
        }
        let ids = tab.session.importMusic(
            [MusicDraft(snapshot: MusicSnapshot(kind: .album, catalogID: "100", title: "Álbum A"))],
            into: nil, artwork: nil, animation: nil)
        await tab.session.toggleMusic(try #require(ids.first))
        try #require(playback.source != nil)
        return (tabs, tab, other, playingRoute, fake)
    }

    @Test("Fechar a aba que toca não para a música")
    func closingThePlayingTabKeepsPlaying() async throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rig = try await makePlayingTabs(library)

        rig.tabs.close(rig.playing.id)
        await waitUntil("a sessão fechar") { rig.playing.session.isClosed }

        #expect(rig.fake.stopCount == 0)
        #expect(rig.fake.status == .playing)
        await rig.tabs.closeAll()
    }

    @Test("O resumo usa os nomes vivos da aba, e não os guardados")
    func summaryPrefersLiveNames() async throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rig = try await makePlayingTabs(library)
        let source = try #require(rig.tabs.musicPlayback.source)

        rig.playing.session.renameItem(source.itemID, to: "Cartão novo")

        let summary = try #require(rig.tabs.musicPlayback.summary(in: rig.tabs))
        #expect(summary.cardTitle == "Cartão novo")
        #expect(source.cardTitle == "Álbum A")
        #expect(summary.boardTitle == rig.playing.title)
        #expect(summary.route == rig.playingRoute)
        await rig.tabs.closeAll()
    }

    @Test("Excluir o mural que toca para a música")
    func deletingThePlayingBoardStops() async throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rig = try await makePlayingTabs(library)

        try await rig.tabs.deleteBoard(rig.playingRoute)

        #expect(rig.fake.stopCount == 1)
        #expect(rig.fake.status == .stopped)
    }

    @Test("Excluir outro mural não para a música")
    func deletingAnotherBoardKeepsPlaying() async throws {
        let (library, directory) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rig = try await makePlayingTabs(library)

        try await rig.tabs.deleteBoard(rig.other)

        #expect(rig.fake.stopCount == 0)
        #expect(rig.fake.status == .playing)
        await rig.tabs.closeAll()
    }
}

/// Conta os pedidos de fechar a janela.
@MainActor
private final class WindowCloses {
    var count = 0
}

/// Anota os murais que `MuralTabs.onBoardClosed` avisou, na ordem.
@MainActor
private final class ClosedBoards {
    var ids: [BoardID] = []
}

/// Os murais que a pessoa excluiu, como `onBoardDeletedByUser` os avisou.
@MainActor
private final class DeletedBoards {
    var ids: [BoardID] = []
}
