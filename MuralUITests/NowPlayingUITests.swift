import AppKit
import XCTest

/// O miniplayer da janela e a seção "Tocando agora" do painel, com o Apple Music falso dos testes de interface: o
/// álbum colado tem as faixas "Faixa 1", "Faixa 2" e "Faixa 3".
final class NowPlayingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ argument: String = "-uiTesting") -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        // O par vem primeiro: depois de "-uiTesting", o macOS o leria como valor daquele argumento.
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", argument]
        app.launch()
        app.activate()
        openExampleBoardIfNeeded(in: app)
        return app
    }

    /// Sem abas, a janela abre com a barra lateral de murais à mostra: abre o rascunho de exemplo e fecha a barra lateral.
    @MainActor
    private func openExampleBoardIfNeeded(in app: XCUIApplication) {
        let exampleCard = app.buttons["The Cottage"].firstMatch
        let back = app.buttons["Voltar"].firstMatch
        if exampleCard.waitForExistence(timeout: 2) || back.exists { return }

        let draftEntry = app.descendants(matching: .any)["welcome-draft-entry"].firstMatch
        XCTAssertTrue(draftEntry.waitForExistence(timeout: 10), "o rascunho de exemplo deveria aparecer na barra lateral")
        draftEntry.click()
        XCTAssertTrue(exampleCard.waitForExistence(timeout: 10), "o rascunho de exemplo deveria abrir no mural")
        let sidebarButton = app.buttons["murals-sidebar-button"].firstMatch
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: 5), "o botão da barra lateral fica ao lado dos semáforos")
        sidebarButton.click()
        XCTAssertTrue(draftEntry.waitForNonExistence(timeout: 5), "o botão fecha a barra lateral")
    }

    /// Cola um álbum do Música, toca pelo botão do cartão e devolve o cartão.
    @MainActor
    @discardableResult
    private func pasteAndPlayAlbum(in app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(app.buttons["The Cottage"].firstMatch.waitForExistence(timeout: 10))
        let json = """
            {"id":"1000000001","type":"albums","href":"/v1/catalog/br/albums/1000000001",
             "attributes":{"name":"Álbum de Teste","artistName":"Banda de Teste","trackCount":3,
              "url":"https://music.apple.com/br/album/album-de-teste/1000000001",
              "artwork":{"url":"https://example.com/capa/{w}x{h}bb.{f}","bgColor":"1f3a5f",
               "textColor1":"ffffff","textColor2":"c9d6e8"},
              "playParams":{"id":"1000000001","kind":"album"}}}
            """
        let entry = NSPasteboardItem()
        entry.setData(Data(json.utf8), forType: NSPasteboard.PasteboardType("com.apple.musicui.genericmusicitem"))
        entry.setString("https://music.apple.com/br/album/album-de-teste/1000000001", forType: .URL)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([entry])
        app.typeKey("v", modifierFlags: .command)

        let card = app.buttons["Álbum de Teste"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "⌘V com um álbum do Música deveria criar um cartão de música")
        card.hover()
        let toggle = app.buttons["music-toggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "o botão de tocar deveria aparecer com o ponteiro sobre o cartão")
        toggle.click()
        return card
    }

    /// Abre o painel pelo item do menu, achado pelo item e não pelo nome do menu, que segue o idioma do sistema ("View" ou
    /// "Visualizar"). A barra de menus pode estar oculta: o ponteiro no topo da tela a mostra.
    @MainActor
    private func openPanel(in app: XCUIApplication) {
        app.activate()
        let menuBar = app.menuBars.firstMatch
        XCTAssertTrue(menuBar.waitForExistence(timeout: 5), "a barra de menus do app deveria existir")
        menuBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).hover()
        let menu = app.menuBars.menuBarItems.containing(.menuItem, identifier: "Abrir Painel de Murais").firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "o comando do painel deveria estar em um menu da barra")
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: menu)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 5), .completed, "o menu deveria aparecer no topo da tela")
        menu.click()
        app.menuItems["Abrir Painel de Murais"].click()
    }

    @MainActor
    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    @MainActor
    private func waitForValue(_ value: String, of element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(
            XCTWaiter().wait(for: [expectation], timeout: 5), .completed,
            "o valor deveria virar “\(value)” (é “\(element.value ?? "")”)", file: file, line: line)
    }

    /// Arrasta a cápsula na horizontal até o meio dela ficar em `midX` (coordenadas de tela).
    @MainActor
    private func drag(_ bar: XCUIElement, toMidX midX: CGFloat, in app: XCUIApplication) {
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: midX - bar.frame.midX, dy: 0))
        start.click(forDuration: 0.2, thenDragTo: end)
    }

    @MainActor
    private func waitForMidX(of element: XCUIElement, near target: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, abs(element.frame.midX - target) > 40 { Thread.sleep(forTimeInterval: 0.1) }
        XCTAssertEqual(element.frame.midX, target, accuracy: 40, "o miniplayer deveria encaixar perto de \(target)", file: file, line: line)
        Thread.sleep(forTimeInterval: 0.4)
    }

    @MainActor
    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    private func waitForLabel(_ label: String, of element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        XCTAssertEqual(
            XCTWaiter().wait(for: [expectation], timeout: 5), .completed,
            "o rótulo deveria virar “\(label)” (é “\(element.label)”)", file: file, line: line)
    }

    @MainActor
    func testMiniPlayerControlsPlaybackAndStops() throws {
        let app = launch()
        pasteAndPlayAlbum(in: app)

        let bar = element("now-playing-bar", in: app)
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "o miniplayer deveria aparecer ao tocar")
        let source = element("now-playing-source", in: app)
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(source.label.contains("Faixa 1"), "o miniplayer deveria mostrar a faixa atual (é “\(source.label)”)")

        let playPause = element("now-playing-play-pause", in: app)
        waitForLabel("Pausar", of: playPause)
        playPause.click()
        waitForLabel("Tocar", of: playPause)
        playPause.click()
        waitForLabel("Pausar", of: playPause)

        element("now-playing-next", in: app).click()
        let next = NSPredicate(format: "label CONTAINS %@", "Faixa 2")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: next, object: source)], timeout: 5), .completed,
            "Próxima faixa deveria mostrar a Faixa 2 (é “\(source.label)”)")

        attachScreenshot("Miniplayer compacto")
        // Parar fica no cartão expandido.
        source.click()
        XCTAssertTrue(element("now-playing-expanded", in: app).waitForExistence(timeout: 5), "clicar no título deveria expandir")
        XCTAssertFalse(app.buttons["Voltar"].exists, "expandir não abre o mural")
        attachScreenshot("Miniplayer expandido")
        element("now-playing-stop", in: app).click()
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5), "Parar deveria esconder o miniplayer")
    }

    @MainActor
    func testExpandedPlayerTogglesShuffleAndRepeat() throws {
        let app = launch()
        pasteAndPlayAlbum(in: app)
        let source = element("now-playing-source", in: app)
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.click()
        let expanded = element("now-playing-expanded", in: app)
        XCTAssertTrue(expanded.waitForExistence(timeout: 5), "clicar no título deveria expandir")
        XCTAssertTrue(element("now-playing-scrubber", in: app).exists, "o álbum tem duração: a barra de tempo aparece")
        XCTAssertTrue(element("now-playing-open", in: app).exists)

        let shuffle = element("now-playing-shuffle", in: app)
        waitForValue("Desligado", of: shuffle)
        shuffle.click()
        waitForValue("Ligado", of: shuffle)

        let repeatButton = element("now-playing-repeat", in: app)
        waitForValue("Desligado", of: repeatButton)
        for expected in ["Tudo", "Uma", "Desligado"] {
            repeatButton.click()
            waitForValue(expected, of: repeatButton)
        }

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(expanded.waitForNonExistence(timeout: 5), "Esc deveria recolher o cartão")
        XCTAssertTrue(element("now-playing-bar", in: app).exists)

        // Clique fora também recolhe.
        source.click()
        XCTAssertTrue(expanded.waitForExistence(timeout: 5))
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.2)).click()
        XCTAssertTrue(expanded.waitForNonExistence(timeout: 5), "clicar fora deveria recolher o cartão")
    }

    /// Arrastar a cápsula na horizontal encaixa nos três pontos do rodapé, e o ponto é lembrado ao reabrir.
    @MainActor
    func testMiniPlayerSnapsToDockAndRemembersIt() throws {
        let app = launch()
        pasteAndPlayAlbum(in: app)
        let bar = element("now-playing-bar", in: app)
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch.frame
        XCTAssertLessThan(bar.frame.midX - window.minX, window.width / 3, "começa à esquerda")
        Thread.sleep(forTimeInterval: 0.5)
        attachScreenshot("Miniplayer à esquerda")

        drag(bar, toMidX: window.midX, in: app)
        waitForMidX(of: bar, near: window.midX)
        attachScreenshot("Miniplayer no centro")

        drag(bar, toMidX: window.maxX - 60, in: app)
        waitForMidX(of: bar, near: window.maxX - 18 - 125)
        attachScreenshot("Miniplayer à direita")

        // O miniplayer à direita ainda expande, e o cartão fica junto da margem direita.
        element("now-playing-source", in: app).click()
        let expanded = element("now-playing-expanded", in: app)
        XCTAssertTrue(expanded.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(expanded.frame.midX, window.midX)
        attachScreenshot("Cartão expandido à direita")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(expanded.waitForNonExistence(timeout: 5))

        app.terminate()
        let reopened = launch("-uiTestingKeep")
        let card = reopened.buttons["Álbum de Teste"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "o cartão de música continua no mural")
        card.hover()
        let toggle = reopened.buttons["music-toggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.click()
        let reopenedBar = element("now-playing-bar", in: reopened)
        XCTAssertTrue(reopenedBar.waitForExistence(timeout: 5))
        let reopenedWindow = reopened.windows.firstMatch.frame
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertGreaterThan(reopenedBar.frame.midX - reopenedWindow.minX, reopenedWindow.width * 2 / 3, "continua à direita")
    }

    @MainActor
    func testQueueEndHidesMiniPlayer() throws {
        let app = launch()
        pasteAndPlayAlbum(in: app)

        let bar = element("now-playing-bar", in: app)
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        let next = element("now-playing-next", in: app)
        for _ in 0..<3 {
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.click()
        }
        // O fim da fila só esconde o miniplayer depois da confirmação (400 ms).
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5), "o fim da fila deveria esconder o miniplayer")
    }

    @MainActor
    func testMiniPlayerStaysAcrossNavigation() throws {
        let app = launch()
        let card = pasteAndPlayAlbum(in: app)
        let bar = element("now-playing-bar", in: app)
        XCTAssertTrue(bar.waitForExistence(timeout: 5))

        card.click()
        XCTAssertTrue(
            app.buttons["Tocar Faixa 1"].firstMatch.waitForExistence(timeout: 5), "a página deveria listar as faixas do álbum")
        XCTAssertTrue(bar.exists, "o miniplayer deveria continuar na página do cartão")

        let back = app.buttons["Voltar"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.click()
        XCTAssertTrue(app.buttons["Álbum de Teste"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(bar.exists, "o miniplayer deveria continuar depois de voltar")
    }

    /// Fechar a aba do mural de onde vem a música não a para: o miniplayer continua em outra aba, o painel mostra a origem e
    /// "Abrir" reabre o mural. Uma segunda aba mantém a janela (e o menu do app) aberta depois do ⌘W.
    @MainActor
    func testClosingTheSourceTabKeepsPlayingInThePanel() throws {
        let app = launch()
        pasteAndPlayAlbum(in: app)
        XCTAssertTrue(element("now-playing-bar", in: app).waitForExistence(timeout: 5))

        let tabs = app.buttons.matching(identifier: "board-tab")
        app.buttons["new-board-button"].firstMatch.click()
        let name = app.textFields["Nome do mural"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        name.typeText("Mural B\r")
        XCTAssertTrue(tabs.matching(NSPredicate(format: "label == %@", "Mural B")).firstMatch.waitForExistence(timeout: 10))
        tabs.matching(NSPredicate(format: "label == %@", "Rascunho de exemplo")).firstMatch.click()
        XCTAssertTrue(app.buttons["Álbum de Teste"].firstMatch.waitForExistence(timeout: 5))

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Álbum de Teste"].firstMatch.waitForNonExistence(timeout: 5), "⌘W deveria fechar a aba")
        XCTAssertEqual(tabs.count, 1, "só a aba do Mural B deveria sobrar")
        waitForLabel("Pausar", of: element("now-playing-play-pause", in: app))

        openPanel(in: app)
        let section = element("menu-bar-now-playing", in: app)
        XCTAssertTrue(section.waitForExistence(timeout: 10), "a música deveria continuar no painel depois de fechar a aba")
        waitForLabel("Pausar", of: element("menu-bar-now-playing-play-pause", in: app))
        XCTAssertTrue(element("menu-bar-now-playing-shuffle", in: app).exists, "o painel mostra o aleatório")
        XCTAssertTrue(element("menu-bar-now-playing-repeat", in: app).exists, "o painel mostra a repetição")
        XCTAssertTrue(element("menu-bar-now-playing-scrubber", in: app).exists, "o painel mostra a barra de tempo")
        attachScreenshot("Painel com o Tocando agora")
        let sourceLine = element("menu-bar-now-playing-source", in: app)
        XCTAssertTrue(sourceLine.exists)
        XCTAssertTrue(
            "\(sourceLine.label) \(sourceLine.value ?? "")".contains("Álbum de Teste"),
            "a linha de origem deveria citar o cartão (é “\(sourceLine.label)”)")

        element("menu-bar-now-playing-open", in: app).click()
        XCTAssertTrue(
            app.buttons["Álbum de Teste"].firstMatch.waitForExistence(timeout: 10), "Abrir deveria reabrir o mural de origem")
        XCTAssertTrue(element("now-playing-bar", in: app).exists, "o miniplayer continua no mural reaberto")
    }
}
