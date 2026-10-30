import AppKit
import XCTest

/// "Editar antes de colar" com o Texto e a Pré-Visualização de verdade, pelo painel da barra de menus.
///
/// Só roda quando pedido, porque mexe em apps de fora e na pasta Downloads real (`~/Downloads/Edições do Mural`): com
/// `TEST_RUNNER_MURAL_REAL_EDITOR_TESTS=1` no ambiente do comando. O app abre com `-realPasteEditor`: o lançador é o de
/// verdade, a cópia do texto fica na biblioteca de testes e a da imagem, no Downloads. Os testes só fecham as janelas das
/// próprias cópias ("Colar em …"), nunca os apps, e só anexam capturas de elementos, nunca da tela inteira.
final class PasteEditRealEditorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MURAL_REAL_EDITOR_TESTS"] == "1",
            "Defina TEST_RUNNER_MURAL_REAL_EDITOR_TESTS=1 para rodar com o Texto e a Pré-Visualização de verdade")
    }

    @MainActor private var textEdit: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.TextEdit") }
    @MainActor private var preview: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.Preview") }

    // MARK: Apoio

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-uiTesting", "-realPasteEditor"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.buttons["The Cottage"].firstMatch.waitForExistence(timeout: 10) || openExampleBoard(in: app))
        return app
    }

    /// Sem abas, a janela abre com a barra lateral: abre o rascunho de exemplo e a fecha.
    @MainActor
    private func openExampleBoard(in app: XCUIApplication) -> Bool {
        let draftEntry = app.descendants(matching: .any)["welcome-draft-entry"].firstMatch
        guard draftEntry.waitForExistence(timeout: 10) else { return false }
        draftEntry.click()
        let sidebarButton = app.buttons["murals-sidebar-button"].firstMatch
        if sidebarButton.waitForExistence(timeout: 10) { sidebarButton.click() }
        return app.buttons["The Cottage"].firstMatch.waitForExistence(timeout: 10)
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
        let isHittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: menu)
        XCTAssertEqual(XCTWaiter.wait(for: [isHittable], timeout: 5), .completed)
        menu.click()
        app.menuItems["Abrir Painel de Murais"].click()
    }

    @MainActor
    private func attach(_ element: XCUIElement, named name: String) {
        guard element.exists else { return }
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func note(_ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = "nota"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func copyWindow(in editor: XCUIApplication) -> XCUIElement {
        editor.windows.matching(NSPredicate(format: "title CONTAINS %@", "Colar em")).firstMatch
    }

    /// Fecha só as janelas das cópias, pelo botão de fechar delas; se perguntar, não salva (apaga a cópia).
    @MainActor
    private func closeCopyWindows(in editor: XCUIApplication) {
        guard editor.state != .notRunning else { return }
        for _ in 0..<4 {
            let window = copyWindow(in: editor)
            guard window.exists else { return }
            let close = window.buttons[XCUIIdentifierCloseWindow]
            if close.exists { close.click() }
            Thread.sleep(forTimeInterval: 1)
            let dialogs = [window.sheets.firstMatch, editor.dialogs.firstMatch]
            for dialog in dialogs where dialog.exists {
                for title in ["Delete Copy", "Apagar Cópia", "Delete", "Don’t Save", "Don't Save", "Não Salvar"]
                where dialog.buttons[title].exists {
                    dialog.buttons[title].click()
                    break
                }
            }
            Thread.sleep(forTimeInterval: 1)
        }
    }

    /// O texto da linha "Copiado:/Editado com …" vem como rótulo ou como valor, conforme o tipo do elemento.
    @MainActor
    private func waitForCopiedLine(in app: XCUIApplication, containing text: String) {
        let line = app.descendants(matching: .any)["menu-bar-copied-line"].firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 10))
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: line)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed, "a linha deveria conter \(text)")
    }

    private static func makePNG(width: Int = 100, height: Int = 50) throws -> Data {
        let rep = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let orange = NSColor(deviceRed: 1, green: 0.58, blue: 0, alpha: 1)
        let indigo = NSColor(deviceRed: 0.35, green: 0.34, blue: 0.84, alpha: 1)
        for x in 0..<width {
            for y in 0..<height {
                rep.setColor(x < width / 2 ? orange : indigo, atX: x, y: y)
            }
        }
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    // MARK: Testes

    /// Texto: o Texto abre a cópia, a pessoa digita sem salvar, e o painel reaberto lê a edição (a leitura coordenada faz o
    /// Texto salvar) e cola o post-it com o texto editado.
    @MainActor
    func testEditingTextInTextEdit() throws {
        let app = launch()
        addTeardownBlock { [self] in closeCopyWindows(in: textEdit) }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.joaocosta.Mural.UITests.Clipboard"))
        pasteboard.clearContents()
        pasteboard.setString("Comprar pão pelo painel", forType: .string)

        openPanelFromMenu(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["menu-bar-coverflow"].firstMatch.waitForExistence(timeout: 10))
        app.typeKey("v", modifierFlags: .command)
        let edit = app.descendants(matching: .any)["menu-bar-paste-option-edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        attach(app.descendants(matching: .any)["menu-bar-paste-section"].firstMatch, named: "real-texto-painel-com-editar")
        edit.click()

        let window = copyWindow(in: textEdit)
        XCTAssertTrue(window.waitForExistence(timeout: 15), "o Texto deveria abrir a cópia")
        note("TextEdit em primeiro plano: \(textEdit.state == .runningForeground) (estado \(textEdit.state.rawValue))")
        note("título da janela: \(window.title)")
        window.textViews.firstMatch.click()
        textEdit.typeKey(.downArrow, modifierFlags: .command)
        textEdit.typeText(" no TextEdit")
        attach(window, named: "real-texto-janela-do-textedit")

        openPanelFromMenu(in: app)
        waitForCopiedLine(in: app, containing: "no TextEdit")
        attach(app.descendants(matching: .any)["menu-bar-paste-section"].firstMatch, named: "real-texto-painel-edicao-pendente")
        XCTAssertTrue(app.descendants(matching: .any)["menu-bar-paste-option-text-sticky"].firstMatch.waitForExistence(timeout: 10))
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(
            app.buttons["Comprar pão pelo painel no TextEdit"].firstMatch.waitForExistence(timeout: 10),
            "o post-it deveria ter o texto digitado no Texto")
    }

    /// Imagem: a Pré-Visualização abre a cópia no Downloads, a pessoa gira a imagem, e o painel reaberto cola a imagem
    /// editada; ao colar, a cópia é apagada e a janela some.
    @MainActor
    func testEditingAnImageInPreview() throws {
        let app = launch()
        addTeardownBlock { [self] in closeCopyWindows(in: preview) }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.joaocosta.Mural.UITests.Clipboard"))
        pasteboard.clearContents()
        pasteboard.setData(try Self.makePNG(), forType: .png)

        openPanelFromMenu(in: app)
        XCTAssertTrue(app.descendants(matching: .any)["menu-bar-coverflow"].firstMatch.waitForExistence(timeout: 10))
        app.typeKey(.tab, modifierFlags: [])
        let edit = app.descendants(matching: .any)["menu-bar-paste-option-edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        attach(app.descendants(matching: .any)["menu-bar-paste-section"].firstMatch, named: "real-imagem-painel-com-editar")
        edit.click()

        let window = copyWindow(in: preview)
        XCTAssertTrue(window.waitForExistence(timeout: 15), "a Pré-Visualização deveria abrir a cópia")
        note("Preview em primeiro plano: \(preview.state == .runningForeground) (estado \(preview.state.rawValue))")
        note("título da janela: \(window.title)")
        attach(window, named: "real-imagem-janela-da-previsualizacao")
        preview.activate()
        preview.typeKey("l", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 2)
        note("janelas da Preview depois de girar: \(preview.windows.allElementsBoundByIndex.map(\.title))")

        openPanelFromMenu(in: app)
        waitForCopiedLine(in: app, containing: "Editado com")
        attach(app.descendants(matching: .any)["menu-bar-paste-section"].firstMatch, named: "real-imagem-painel-edicao-pendente")
        XCTAssertTrue(app.descendants(matching: .any)["menu-bar-paste-option-asRead"].firstMatch.waitForExistence(timeout: 10))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(
            app.buttons["Imagem colada"].firstMatch.waitForExistence(timeout: 10),
            "a imagem editada deveria entrar no mural")

        let gone = copyWindow(in: preview).waitForNonExistence(timeout: 8)
        note("depois de colar, janelas da Preview: \(preview.windows.allElementsBoundByIndex.map(\.title)); janela sumiu: \(gone)")
        XCTAssertTrue(gone, "apagar a cópia deveria fechar a janela da Pré-Visualização (ou há uma janela \"copy\")")
    }
}
