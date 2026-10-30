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

    /// Anexa só a seção de colar do painel: uma captura da tela inteira levaria o que há em outros apps.
    @MainActor
    private func attachPasteSection(of app: XCUIApplication, named name: String) {
        let section = app.descendants(matching: .any)["menu-bar-paste-section"].firstMatch
        XCTAssertTrue(section.waitForExistence(timeout: 5), "a seção de colar do painel deveria existir")
        let attachment = XCTAttachment(screenshot: section.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Abre o painel, lê o texto copiado com ⌘V, escolhe "Editar com …" e espera o painel fechar. O lançador dos testes não
    /// abre app nenhum: só simula a edição, acrescentando " (editado)" ao arquivo.
    @MainActor
    private func startEditingText(_ text: String, in app: XCUIApplication) {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.joaocosta.Mural.UITests.Clipboard"))
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        openPanelFromMenu(in: app)
        let coverflow = app.descendants(matching: .any)["menu-bar-coverflow"].firstMatch
        XCTAssertTrue(coverflow.waitForExistence(timeout: 10), "o painel deveria abrir com a vitrine de murais")
        app.typeKey("v", modifierFlags: .command)
        let edit = app.descendants(matching: .any)["menu-bar-paste-option-edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "⌘V lê o texto e oferece editar antes de colar")
        attachPasteSection(of: app, named: "painel-texto-com-editar")

        edit.click()
        XCTAssertTrue(coverflow.waitForNonExistence(timeout: 10), "o painel fecha depois de abrir o editor")
    }

    /// Abre o painel de novo e espera a edição pendente aparecer, já lida de volta.
    @MainActor
    private func reopenPanelWithPendingEdit(in app: XCUIApplication) {
        openPanelFromMenu(in: app)
        let copiedLine = app.descendants(matching: .any)["menu-bar-copied-line"].firstMatch
        XCTAssertTrue(copiedLine.waitForExistence(timeout: 10), "o painel reaberto deveria mostrar a linha do conteúdo")
        // Conforme o tipo do elemento, o texto da linha chega como rótulo ou como valor.
        let edited = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Editado com", "Editado com")
        expectation(for: edited, evaluatedWith: copiedLine)
        waitForExpectations(timeout: 10)
        let edit = app.descendants(matching: .any)["menu-bar-paste-option-edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 10), "com a edição lida, as opções aparecem")
    }

    /// Escolher "Editar com …" no painel abre a cópia no editor e fecha o painel; ao reabrir, o painel mostra a edição
    /// pendente (com as opções de continuar e descartar) e Return cola o post-it com o texto editado.
    @MainActor
    func testEditingTextBeforePastingFromThePanel() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["The Cottage"].firstMatch.waitForExistence(timeout: 10))
        startEditingText("Comprar pão pelo painel", in: app)

        reopenPanelWithPendingEdit(in: app)
        attachPasteSection(of: app, named: "painel-edicao-pendente")
        XCTAssertTrue(app.descendants(matching: .any)["menu-bar-paste-option-discardEdit"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["menu-bar-paste-option-edit"].firstMatch.exists)

        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(
            app.buttons["Comprar pão pelo painel (editado)"].firstMatch.waitForExistence(timeout: 10),
            "Return deveria colar o post-it com o texto editado no mural do centro")
    }

    /// Descartar a edição devolve o painel ao que está na área de transferência.
    @MainActor
    func testDiscardingAnEditReturnsToTheClipboard() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["The Cottage"].firstMatch.waitForExistence(timeout: 10))
        startEditingText("Comprar pão pelo painel", in: app)

        reopenPanelWithPendingEdit(in: app)
        let discard = app.descendants(matching: .any)["menu-bar-paste-option-discardEdit"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.click()

        XCTAssertTrue(discard.waitForNonExistence(timeout: 10), "a opção de descartar some")
        let copiedLine = app.descendants(matching: .any)["menu-bar-copied-line"].firstMatch
        let copied = NSPredicate(
            format: "(label CONTAINS %@ OR value CONTAINS %@) AND NOT (label CONTAINS %@ OR value CONTAINS %@)",
            "Copiado:", "Copiado:", "Editado com", "Editado com")
        expectation(for: copied, evaluatedWith: copiedLine)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(
            app.descendants(matching: .any)["menu-bar-paste-option-edit"].firstMatch.waitForExistence(timeout: 5),
            "a opção de editar volta")
        attachPasteSection(of: app, named: "painel-depois-de-descartar")
    }

    /// Uma imagem copiada também pode ser editada antes de colar: o painel reaberto lê o PNG de volta e Return o cola.
    @MainActor
    func testEditingAnImageBeforePastingFromThePanel() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["The Cottage"].firstMatch.waitForExistence(timeout: 10))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.joaocosta.Mural.UITests.Clipboard"))
        pasteboard.clearContents()
        pasteboard.setData(try Self.makePNG(), forType: .png)

        openPanelFromMenu(in: app)
        let coverflow = app.descendants(matching: .any)["menu-bar-coverflow"].firstMatch
        XCTAssertTrue(coverflow.waitForExistence(timeout: 10), "o painel deveria abrir com a vitrine de murais")
        app.typeKey(.tab, modifierFlags: [])
        let edit = app.descendants(matching: .any)["menu-bar-paste-option-edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "Tab mostra as maneiras de colar, com a de editar")
        edit.click()
        XCTAssertTrue(coverflow.waitForNonExistence(timeout: 10), "o painel fecha depois de abrir o editor")

        reopenPanelWithPendingEdit(in: app)
        attachPasteSection(of: app, named: "painel-imagem-editada")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(
            app.buttons["Imagem colada"].firstMatch.waitForExistence(timeout: 10),
            "Return deveria colar a imagem editada no mural do centro")
    }

    /// PNG de 40×30 gerado no teste. As cores têm componentes RGB explícitos: uma cor do sistema não converte para o espaço
    /// do bitmap e deixaria todos os pixels transparentes.
    private static func makePNG(width: Int = 40, height: Int = 30) throws -> Data {
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

    /// O atributo de foco do teclado da acessibilidade; `XCUIElement` não o expõe como propriedade no macOS.
    private func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    /// Tab e ⇧Tab só andam entre as etapas do conteúdo: os botões do rodapé são só para o mouse.
    @MainActor
    func testTabNeverFocusesTheFooter() {
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
        XCTAssertFalse(hasKeyboardFocus(openBoard), "Tab na última etapa não deveria focar Abrir mural")
        app.typeKey(.tab, modifierFlags: .shift)
        XCTAssertFalse(hasKeyboardFocus(openBoard), "⇧Tab na primeira etapa não deveria focar nenhum botão do rodapé")
        app.typeKey(.tab, modifierFlags: [])
        app.typeKey(.space, modifierFlags: [])

        let coverflow = app.descendants(matching: .any)["menu-bar-coverflow"].firstMatch
        XCTAssertFalse(
            coverflow.waitForNonExistence(timeout: 2),
            "Espaço não deveria ativar Abrir mural: o painel continua aberto")
    }
}
