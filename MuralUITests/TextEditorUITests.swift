import AppKit
import XCTest

/// A janela do editor de texto aberta de verdade: abrir pelo menu, digitar, formatar pelo atalho e fechar com a confirmação.
final class TextEditorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-uiTesting"]
        app.launch()
        app.activate()
        return app
    }

    /// Abre o editor pelo item "Abrir Editor de Texto" do menu Visualizar.
    @MainActor
    private func openEditorFromMenu(in app: XCUIApplication) {
        app.activate()
        let menuBar = app.menuBars.firstMatch
        XCTAssertTrue(menuBar.waitForExistence(timeout: 5), "a barra de menus do app deveria existir")
        menuBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).hover()
        let menu = app.menuBars.menuBarItems
            .containing(.menuItem, identifier: "Abrir Editor de Texto")
            .firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "o comando do editor deveria estar em um menu da barra")
        let menuIsHittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: menu)
        XCTAssertEqual(XCTWaiter.wait(for: [menuIsHittable], timeout: 5), .completed)
        menu.click()
        app.menuItems["Abrir Editor de Texto"].click()
    }

    private func editorWindow(in app: XCUIApplication) -> XCUIElement {
        app.windows["Editor de texto"].firstMatch
    }

    /// O texto do campo, por valor de acessibilidade.
    private func fieldText(in app: XCUIApplication) -> String {
        editorWindow(in: app).textViews.firstMatch.value as? String ?? ""
    }

    @MainActor
    func testTypeFormatCloseWithConfirmationAndReopenEmpty() throws {
        let app = launch()
        openEditorFromMenu(in: app)
        let window = editorWindow(in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 10), "a janela do editor deveria abrir")

        let field = window.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("ovos\nleite")
        // ⌘⇧L: lista com marcadores.
        app.typeKey("a", modifierFlags: .command)
        app.typeKey("l", modifierFlags: [.command, .shift])
        let isList = NSPredicate { _, _ in self.fieldText(in: app).hasPrefix("- ") }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isList, object: nil)], timeout: 5), .completed)
        XCTAssertEqual(fieldText(in: app).lowercased(), "- ovos\n- leite")
        let listText = fieldText(in: app)

        // Fechar com texto pergunta; "Cancelar" mantém o texto.
        window.buttons[XCUIIdentifierCloseWindow].click()
        let discardButton = app.buttons["Descartar"].firstMatch
        XCTAssertTrue(discardButton.waitForExistence(timeout: 5), "fechar com texto deveria pedir confirmação")
        // O botão de cancelar é do sistema (o rótulo segue o idioma do Mac): Esc cancela.
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(discardButton.waitForNonExistence(timeout: 5), "a pergunta some")
        XCTAssertTrue(window.exists, "Cancelar mantém a janela")
        XCTAssertEqual(fieldText(in: app), listText)

        // "Descartar" fecha a janela.
        window.buttons[XCUIIdentifierCloseWindow].click()
        let discard = app.buttons["Descartar"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.click()
        XCTAssertTrue(window.waitForNonExistence(timeout: 5), "Descartar fecha a janela")

        // Reaberto, o editor está vazio e fecha direto, sem pergunta.
        openEditorFromMenu(in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertEqual(fieldText(in: app), "")
        window.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(window.waitForNonExistence(timeout: 5), "vazio fecha sem confirmação")
        XCTAssertFalse(app.buttons["Descartar"].exists)
    }
}
