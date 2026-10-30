import AppKit
import XCTest

/// A galeria "Colar no mural", aberta de verdade pelo "Colar no mural…" do editor de texto.
final class PasteDestinationUITests: XCTestCase {
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
        XCTAssertTrue(menuBar.waitForExistence(timeout: 5))
        menuBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).hover()
        let menu = app.menuBars.menuBarItems.containing(.menuItem, identifier: "Abrir Editor de Texto").firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: menu)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 5), .completed)
        menu.click()
        app.menuItems["Abrir Editor de Texto"].click()
    }

    @MainActor
    func testGalleryPastesTheEditorTextAndTheEditorStaysOpen() throws {
        let app = launch()
        openEditorFromMenu(in: app)
        let editor = app.windows["Editor de texto"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let field = editor.textViews.firstMatch
        field.click()
        field.typeText("Comprar pão")

        // ⌘↩ (o comando do menu "Colar no Mural…") abre a galeria.
        app.typeKey(.return, modifierFlags: .command)
        let gallery = app.windows["Colar no mural"].firstMatch
        XCTAssertTrue(gallery.waitForExistence(timeout: 10), "a galeria deveria abrir")
        XCTAssertTrue(app.descendants(matching: .any)["paste-destination-window"].firstMatch.waitForExistence(timeout: 5))

        // O texto curto sugere o post-it, já escolhido.
        let sticky = app.descendants(matching: .any)["paste-destination-kind-sticky"].firstMatch
        XCTAssertTrue(sticky.waitForExistence(timeout: 5))
        let isSelected = NSPredicate { _, _ in sticky.isSelected }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isSelected, object: nil)], timeout: 5), .completed)

        let attachment = XCTAttachment(screenshot: gallery.screenshot())
        attachment.name = "galeria-claro"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.typeKey(.return, modifierFlags: [])
        let status = app.descendants(matching: .any)["paste-destination-status"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10), "o resultado do colar aparece")
        let pasted = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Colado em", "Colado em")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: pasted, object: status)], timeout: 10), .completed)

        XCTAssertTrue(gallery.waitForNonExistence(timeout: 10), "a galeria fecha depois de um segundo")
        XCTAssertTrue(editor.exists, "o editor continua aberto")
        XCTAssertEqual(editor.textViews.firstMatch.value as? String, "Comprar pão", "com o texto")

        // Limpa para os próximos testes: fecha o editor descartando o texto.
        editor.buttons[XCUIIdentifierCloseWindow].click()
        let discard = app.buttons["Descartar"].firstMatch
        if discard.waitForExistence(timeout: 5) { discard.click() }
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testTextCardAsksForTheTitleBeforePasting() throws {
        let app = launch()
        openEditorFromMenu(in: app)
        let editor = app.windows["Editor de texto"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        let field = editor.textViews.firstMatch
        field.click()
        field.typeText("Comprar pão")
        app.typeKey(.return, modifierFlags: .command)
        let gallery = app.windows["Colar no mural"].firstMatch
        XCTAssertTrue(gallery.waitForExistence(timeout: 10), "a galeria deveria abrir")

        // ↓ vai do post-it sugerido ao Card de texto.
        let textKind = app.descendants(matching: .any)["paste-destination-kind-text"].firstMatch
        XCTAssertTrue(textKind.waitForExistence(timeout: 5))
        app.typeKey(.downArrow, modifierFlags: [])
        let isSelected = NSPredicate { _, _ in textKind.isSelected }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isSelected, object: nil)], timeout: 5), .completed)

        // Return pergunta o título, sem colar.
        app.typeKey(.return, modifierFlags: [])
        let title = app.descendants(matching: .any)["paste-title-field"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "colar como Card de texto deveria pedir o título")
        XCTAssertEqual(title.value as? String, "Comprar pão", "começa com o título tirado do texto")
        let attachment = XCTAttachment(screenshot: gallery.screenshot())
        attachment.name = "titulo-do-card"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Esc volta à galeria sem colar, e o botão Cancelar também.
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "Esc fecha a folha")
        XCTAssertTrue(gallery.exists, "e a galeria continua aberta")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(title.waitForExistence(timeout: 5), "o teclado voltou à galeria")
        app.descendants(matching: .any)["paste-title-cancel"].firstMatch.click()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "Cancelar fecha a folha")

        // Pedir de novo e confirmar cola.
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.typeKey("a", modifierFlags: .command)
        title.typeText("Mercado\n")
        let status = app.descendants(matching: .any)["paste-destination-status"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10), "o resultado do colar aparece")
        XCTAssertTrue(gallery.waitForNonExistence(timeout: 10), "a galeria fecha depois de colar")

        editor.buttons[XCUIIdentifierCloseWindow].click()
        let discard = app.buttons["Descartar"].firstMatch
        if discard.waitForExistence(timeout: 5) { discard.click() }
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
    }
}
