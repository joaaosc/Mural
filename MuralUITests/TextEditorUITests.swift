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

    // MARK: Anexos

    /// Põe na área de transferência uma imagem azul, que não se confunde com nada do editor.
    private func copyBlueImage() throws {
        let image = NSImage(size: NSSize(width: 64, height: 48), flipped: false) { rect in
            NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1).setFill()
            rect.fill()
            return true
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
    }

    /// Quantos pontos azuis, numa grade de 6 pixels, há na captura do campo.
    private func bluePoints(in field: XCUIElement) throws -> Int {
        let tiff = try XCTUnwrap(field.screenshot().image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var count = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 6) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 6) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.blueComponent > 0.8, color.redComponent < 0.25, color.greenComponent < 0.35 { count += 1 }
            }
        }
        return count
    }

    /// O vídeo do defeito: colada no fim, a imagem ficava em branco até se digitar depois dela, e ao voltar com o cursor sumia de
    /// novo, com o texto de baixo saltando uma linha.
    @MainActor
    func testPastedImageStaysVisibleWhileTheCursorMoves() throws {
        let app = launch()
        openEditorFromMenu(in: app)
        let window = editorWindow(in: app)
        XCTAssertTrue(window.waitForExistence(timeout: 10), "a janela do editor deveria abrir")
        let field = window.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("eeee")
        try copyBlueImage()
        app.typeKey("v", modifierFlags: .command)

        Thread.sleep(forTimeInterval: 0.3)
        let screenshot = XCTAttachment(screenshot: field.screenshot())
        screenshot.name = "imagem-colada"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let wholeImage = try bluePoints(in: field)
        XCTAssertGreaterThan(wholeImage, 100, "a imagem deveria aparecer logo depois de colar")

        // Sem nada digitado: o cursor sobe, desce e volta, e a imagem fica igual em cada passo.
        for (key, moment) in [
            (XCUIKeyboardKey.upArrow, "cursor acima"), (.downArrow, "cursor abaixo"), (.leftArrow, "cursor à esquerda"),
            (.rightArrow, "cursor à direita"),
        ] {
            app.typeKey(key, modifierFlags: [])
            Thread.sleep(forTimeInterval: 0.15)
            XCTAssertEqual(try bluePoints(in: field), wholeImage, "\(moment): a imagem deveria continuar inteira")
        }

        // Escrever continua na linha de baixo, com a imagem à vista. Números: a correção automática do campo não mexe neles.
        field.typeText("123")
        XCTAssertEqual(try bluePoints(in: field), wholeImage, "digitar não mexe na imagem")
        let text = fieldText(in: app)
        XCTAssertTrue(text.hasSuffix("\n123"), "o texto fica na linha de baixo da imagem: \(text)")

        // ⌫ até o começo da linha e mais um apaga a imagem; ⌘Z a devolve.
        for _ in 0..<4 { app.typeKey(.delete, modifierFlags: []) }
        let isGone = NSPredicate { _, _ in ((try? self.bluePoints(in: field)) ?? 1) == 0 }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isGone, object: nil)], timeout: 5), .completed)
        app.typeKey("z", modifierFlags: .command)
        let isBack = NSPredicate { _, _ in ((try? self.bluePoints(in: field)) ?? 0) == wholeImage }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isBack, object: nil)], timeout: 5), .completed)
    }
}
