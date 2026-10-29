import AppKit
import XCTest

/// O miniplayer da janela e a seção "Tocando agora" do painel, com o Apple Music falso dos testes de interface: o
/// álbum colado tem as faixas "Faixa 1", "Faixa 2" e "Faixa 3".
final class NowPlayingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        // O par vem primeiro: depois de "-uiTesting", o macOS o leria como valor daquele argumento.
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-uiTesting"]
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

    @MainActor
    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
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

        element("now-playing-stop", in: app).click()
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5), "Parar deveria esconder o miniplayer")
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

    @MainActor
    func testClosingTheSourceTabKeepsPlayingInThePanel() throws {
        let app = launch()
        pasteAndPlayAlbum(in: app)
        XCTAssertTrue(element("now-playing-bar", in: app).waitForExistence(timeout: 5))

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Álbum de Teste"].firstMatch.waitForNonExistence(timeout: 5), "⌘W deveria fechar a janela")
        app.activate()

        app.menuBars.menuBarItems["Visualizar"].click()
        app.menuItems["Abrir Painel de Murais"].click()
        let section = element("menu-bar-now-playing", in: app)
        XCTAssertTrue(section.waitForExistence(timeout: 10), "a música deveria continuar no painel depois de fechar a janela")
        waitForLabel("Pausar", of: element("menu-bar-now-playing-play-pause", in: app))

        element("menu-bar-now-playing-open", in: app).click()
        XCTAssertTrue(
            element("now-playing-bar", in: app).waitForExistence(timeout: 10),
            "Abrir deveria reabrir o mural, com o miniplayer")
    }
}
