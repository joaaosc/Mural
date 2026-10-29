import AppKit
import XCTest

/// O painel da barra de menus aberto de verdade: colar o que foi copiado no mural do centro da vitrine.
///
/// Abre o painel pelo item do menu Visualizar (o mesmo painel do ícone, no meio da tela): o ícone da barra de menus não é
/// um alvo estável para o XCUITest.
final class MenuBarPanelUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        // Ignora o estado salvo de execuções anteriores. O par vem primeiro: depois de "-uiTesting", o macOS o leria como
        // valor daquele argumento.
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-uiTesting"]
        app.launch()
        app.activate()
        openExampleBoardIfNeeded(in: app)
        return app
    }

    /// Sem abas, a janela abre com a barra lateral de murais à mostra: abre o rascunho de exemplo (que passa a ser o mural da
    /// aba ativa, e por isso o do centro da vitrine) e fecha a barra lateral.
    @MainActor
    private func openExampleBoardIfNeeded(in app: XCUIApplication) {
        let exampleCard = app.buttons["The Cottage"].firstMatch
        let back = app.buttons["Voltar"].firstMatch
        if exampleCard.waitForExistence(timeout: 2) || back.exists { return }

        let draftEntry = app.descendants(matching: .any)["welcome-draft-entry"].firstMatch
        XCTAssertTrue(draftEntry.waitForExistence(timeout: 10), "o rascunho de exemplo deveria aparecer na barra lateral")
        draftEntry.click()
        let openedBoard = NSPredicate { _, _ in exampleCard.exists || back.exists }
        let expectation = XCTNSPredicateExpectation(predicate: openedBoard, object: nil)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 10),
            .completed,
            "o rascunho de exemplo deveria abrir no mural"
        )
        let sidebarButton = app.buttons["murals-sidebar-button"].firstMatch
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: 5), "o botão da barra lateral fica ao lado dos semáforos")
        sidebarButton.click()
        XCTAssertTrue(draftEntry.waitForNonExistence(timeout: 5), "o botão fecha a barra lateral")
    }

    @MainActor
    private func openPanelFromMenu(in app: XCUIApplication) {
        app.activate()
        let menuBar = app.menuBars.firstMatch
        XCTAssertTrue(menuBar.waitForExistence(timeout: 5), "a barra de menus do app deveria existir")
        menuBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).hover()

        let menu = app.menuBars.menuBarItems
            .containing(.menuItem, identifier: "Abrir Painel de Murais")
            .firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "o comando do painel deveria estar em um menu da barra")
        let menuIsVisible = NSPredicate(format: "isHittable == true")
        let menuIsHittable = XCTNSPredicateExpectation(predicate: menuIsVisible, object: menu)
        XCTAssertEqual(
            XCTWaiter.wait(for: [menuIsHittable], timeout: 5), .completed,
            "a barra de menus oculta aparece quando o ponteiro chega ao topo da tela"
        )
        menu.click()
        app.menuItems["Abrir Painel de Murais"].click()
    }

    /// ⌘V no painel lê o texto copiado e oferece os tipos de cartão; Return cola o post-it sugerido no mural do centro, que
    /// é o da aba ativa.
    @MainActor
    func testPastedTextFromThePanelBecomesStickyOnTheCenterBoard() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["The Cottage"].firstMatch.waitForExistence(timeout: 10))

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.joaocosta.Mural.UITests.Clipboard"))
        pasteboard.clearContents()
        pasteboard.setString("Comprar pão pelo painel", forType: .string)

        openPanelFromMenu(in: app)
        let coverflow = app.descendants(matching: .any)["menu-bar-coverflow"].firstMatch
        XCTAssertTrue(coverflow.waitForExistence(timeout: 10), "o painel deveria abrir com a vitrine de murais")

        app.typeKey("v", modifierFlags: .command)
        let sticky = app.descendants(matching: .any)["menu-bar-paste-option-text-sticky"].firstMatch
        XCTAssertTrue(sticky.waitForExistence(timeout: 5), "⌘V lê o texto e oferece colar como post-it")

        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(
            app.buttons["Comprar pão pelo painel"].firstMatch.waitForExistence(timeout: 10),
            "Return deveria colar o post-it no mural do centro")
    }

    /// Tab mantém o fluxo pelas etapas e, sem opções de colagem, chega ao primeiro botão do rodapé.
    @MainActor
    func testTabMovesFocusFromBoardsToFooter() {
        let app = launch()
        openPanelFromMenu(in: app)

        let openBoard = app.buttons["menu-bar-open-board"].firstMatch
        XCTAssertTrue(openBoard.waitForExistence(timeout: 10), "o rodapé deveria oferecer Abrir mural")
        XCTAssertTrue(openBoard.isEnabled, "a fixture seleciona um mural para abrir")
        XCTAssertFalse(
            app.descendants(matching: .any)["menu-bar-paste-option-text-sticky"].exists,
            "a área de transferência nomeada começa sem opções de colagem neste teste"
        )
        app.typeKey(.tab, modifierFlags: [])
        app.typeKey(.space, modifierFlags: [])

        XCTAssertTrue(
            app.descendants(matching: .any)["menu-bar-coverflow"].waitForNonExistence(timeout: 5),
            "Tab deveria focar Abrir mural e Espaço deveria ativar o botão")
    }
}
