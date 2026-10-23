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

    /// ⌘V no painel lê o texto copiado e oferece os tipos de cartão; Return cola o post-it sugerido no mural do centro, que
    /// é o da aba ativa.
    @MainActor
    func testPastedTextFromThePanelBecomesStickyOnTheCenterBoard() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["The Cottage"].firstMatch.waitForExistence(timeout: 10))

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("Comprar pão pelo painel", forType: .string)

        app.menuBars.menuBarItems["Visualizar"].click()
        app.menuItems["Abrir Painel de Murais"].click()
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
}
