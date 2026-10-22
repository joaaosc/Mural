import AppKit
import XCTest

/// Abre o app de verdade com um mural de teste (pasta própria dentro do contêiner).
final class MuralUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ argument: String = "-uiTesting") -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        // Ignora o estado salvo de execuções anteriores (janelas de testes antigos). O par vem
        // primeiro: depois de "-uiTesting", o macOS o leria como valor daquele argumento.
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", argument]
        app.launch()
        app.activate()
        openExampleBoardIfNeeded(in: app)
        // O ponteiro herdado do teste anterior pode passar por uma pasta a caminho do próximo
        // clique e abrir a prévia por cima dos cartões vizinhos: começa sempre embaixo, no vazio.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)).hover()
        return app
    }

    @MainActor
    private func openExampleBoardIfNeeded(in app: XCUIApplication) {
        let exampleCard = app.buttons["The Cottage"].firstMatch
        let back = app.buttons["Voltar"].firstMatch
        if exampleCard.waitForExistence(timeout: 2) || back.exists { return }

        // A biblioteca costuma ser a janela que abre: com o rascunho já visível, nada de aba ou menu. O menu
        // Window falha quando a barra de menus do Mac está configurada para se esconder sozinha.
        let draftEntry = app.descendants(matching: .any)["welcome-draft-entry"].firstMatch
        let libraryTab = app.tabs["Murais"].firstMatch
        if draftEntry.waitForExistence(timeout: 2) {
            // A biblioteca já está na frente.
        } else if libraryTab.waitForExistence(timeout: 2) {
            libraryTab.click()
        } else {
            let windowMenu = app.menuBars.menuBarItems["Window"].firstMatch
            if windowMenu.waitForExistence(timeout: 2) {
                windowMenu.click()
                let libraryWindow = app.menuItems["Murais"].firstMatch
                if libraryWindow.waitForExistence(timeout: 2) {
                    libraryWindow.click()
                }
            }
        }

        XCTAssertTrue(draftEntry.waitForExistence(timeout: 10), "o rascunho de exemplo deveria aparecer na biblioteca")
        draftEntry.doubleClick()
        let openedBoard = NSPredicate { _, _ in exampleCard.exists || back.exists }
        let expectation = XCTNSPredicateExpectation(predicate: openedBoard, object: nil)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 10),
            .completed,
            "o rascunho de exemplo deveria abrir no mural"
        )
    }

    @MainActor
    func testBoardOpensFolderAndGoesBack() throws {
        let app = launch()
        let folder = app.buttons["The Cottage"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 10), "a pasta de exemplo deveria estar no mural")
        XCTAssertFalse(app.buttons["Voltar"].exists, "no mural não há para onde voltar")

        // Um filtro ligado no mural não deve atravessar para dentro da pasta.
        app.buttons["Pastas"].firstMatch.click()
        XCTAssertTrue(app.buttons["Pastas"].firstMatch.isSelected)

        folder.click()
        let back = app.buttons["Voltar"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Meeting Notes – Andrea and Jasmine"].exists, "cartão de dentro da pasta")
        XCTAssertFalse(app.buttons["Pastas"].exists, "dentro da pasta não há filtro de pastas")
        XCTAssertFalse(app.buttons["Notas"].firstMatch.isSelected, "cada nível começa sem filtro")

        // Os detalhes da pasta ficam no botão de informação.
        app.buttons["Informações da pasta"].firstMatch.click()
        let tag = app.staticTexts["CLIENT 001"]
        XCTAssertTrue(tag.waitForExistence(timeout: 5), "etiqueta no popover")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(tag.waitForNonExistence(timeout: 5), "Esc fecha o popover")
        XCTAssertTrue(back.exists, "e não sai da pasta")

        back.click()
        XCTAssertTrue(back.waitForNonExistence(timeout: 5))
    }

    /// Defeito relatado: um clique perto da borda do botão Voltar (fora do desenho da seta)
    /// acendia o vidro, mas não voltava. O clique simulado no centro nunca mostrava o problema.
    @MainActor
    func testBackRespondsToClickNearItsEdge() throws {
        let app = launch()
        let folder = app.buttons["The Cottage"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 10))
        folder.click()

        let back = app.buttons["Voltar"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.8)).click()
        XCTAssertTrue(back.waitForNonExistence(timeout: 5), "um clique em qualquer ponto do botão deve voltar")
    }

    /// Aproximar pelo teclado mantém o centro da janela parado: um cartão se afasta do
    /// centro exatamente na proporção do zoom (1,25×), em vez de o mural "fugir" para o canto.
    @MainActor
    func testZoomInKeepsWindowCenterInPlace() throws {
        let app = launch()
        let card = app.buttons["Running list of stuff"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let window = app.windows.firstMatch.frame
        let center = CGPoint(x: window.midX, y: window.midY)
        let before = CGPoint(x: card.frame.midX, y: card.frame.midY)

        app.typeKey("=", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 1.0)

        let after = CGPoint(x: card.frame.midX, y: card.frame.midY)
        let expected = CGPoint(x: center.x + (before.x - center.x) * 1.25, y: center.y + (before.y - center.y) * 1.25)
        XCTAssertEqual(after.x, expected.x, accuracy: 6)
        XCTAssertEqual(after.y, expected.y, accuracy: 6)
    }

    /// Arrastar um cartão solto o move sem abri-lo, e a nova posição sobrevive a fechar e reabrir o app.
    @MainActor
    func testDraggingCardMovesItAndKeepsPosition() throws {
        let app = launch()
        let card = app.buttons["Things I need"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let before = card.frame

        drag(card, dx: 40, dy: 200)

        XCTAssertFalse(app.buttons["Voltar"].waitForExistence(timeout: 1), "arrastar não deve abrir o cartão")
        let moved = card.frame
        XCTAssertEqual(moved.minX - before.minX, 40, accuracy: 4)
        XCTAssertEqual(moved.minY - before.minY, 200, accuracy: 4)

        // A janela pode abrir em outro lugar da tela: compara a posição dentro dela.
        let window = app.windows.firstMatch.frame
        let relative = CGPoint(x: moved.minX - window.minX, y: moved.minY - window.minY)

        app.terminate()
        let reopened = launch("-uiTestingKeep")
        let again = reopened.buttons["Things I need"].firstMatch
        XCTAssertTrue(again.waitForExistence(timeout: 10), "o cartão deveria continuar após reabrir")
        let reopenedWindow = reopened.windows.firstMatch.frame
        XCTAssertEqual(again.frame.minX - reopenedWindow.minX, relative.x, accuracy: 4)
        XCTAssertEqual(again.frame.minY - reopenedWindow.minY, relative.y, accuracy: 4)
    }

    /// Arrastar a pasta com a prévia aberta leva a prévia junto e não abre a pasta.
    @MainActor
    func testDraggingFolderMovesItsPreviewToo() throws {
        let app = launch()
        let folder = app.buttons["The Cottage"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 10))
        folder.hover()
        let peekCard = app.buttons["Meeting Notes – Andrea and Jasmine"].firstMatch
        XCTAssertTrue(peekCard.waitForExistence(timeout: 5), "a prévia deveria abrir com o ponteiro sobre a pasta")
        // Espera a entrada da prévia terminar, para medir os quadros finais.
        Thread.sleep(forTimeInterval: 0.6)
        let folderBefore = folder.frame
        let peekBefore = peekCard.frame

        drag(folder, dx: 160, dy: 0)

        XCTAssertFalse(app.buttons["Voltar"].waitForExistence(timeout: 1), "arrastar não deve abrir a pasta")
        XCTAssertTrue(peekCard.exists, "a prévia deveria continuar aberta")
        XCTAssertEqual(folder.frame.minX - folderBefore.minX, 160, accuracy: 4)
        XCTAssertEqual(peekCard.frame.minX - peekBefore.minX, 160, accuracy: 4)
    }

    /// Com zoom, o cartão acompanha o ponteiro: o arrasto é medido em pontos do mural, sem o zoom.
    @MainActor
    func testDraggingWithZoomKeepsCardUnderPointer() throws {
        let app = launch()
        let card = app.buttons["Running list of stuff"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))

        app.typeKey("=", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 1.0)
        let before = card.frame

        drag(card, dx: 0, dy: 150)

        XCTAssertFalse(app.buttons["Voltar"].waitForExistence(timeout: 1), "arrastar não deve abrir o cartão")
        let after = card.frame
        XCTAssertEqual(after.minX - before.minX, 0, accuracy: 5)
        XCTAssertEqual(after.minY - before.minY, 150, accuracy: 5)
    }

    /// Soltar um cartão sobre uma pasta o guarda nela: some do mural, aparece dentro e continua lá após reabrir.
    @MainActor
    func testDroppingCardOnFolderStoresIt() throws {
        let app = launch()
        let card = app.buttons["Today"].firstMatch
        let folder = app.buttons["44th Street"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(folder.waitForExistence(timeout: 10))

        let start = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.click(forDuration: 0.3, thenDragTo: folder.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))

        // Afasta o ponteiro das pastas, para nenhuma prévia mostrar o cartão guardado.
        app.buttons["Alpha"].firstMatch.hover()
        XCTAssertTrue(app.buttons["Today"].waitForNonExistence(timeout: 3), "o cartão guardado sai do mural")

        folder.click()
        XCTAssertTrue(app.buttons["Voltar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 5), "o cartão aparece dentro da pasta")

        app.terminate()
        let reopened = launch("-uiTestingKeep")
        let restoredBack = reopened.buttons["Voltar"].firstMatch
        XCTAssertTrue(restoredBack.waitForExistence(timeout: 10), "a pasta aberta deveria ser restaurada")
        XCTAssertTrue(reopened.buttons["Today"].waitForExistence(timeout: 5), "o cartão continua dentro da pasta após reabrir")

        restoredBack.click()
        XCTAssertTrue(restoredBack.waitForNonExistence(timeout: 5))
        let alpha = reopened.buttons["Alpha"].firstMatch
        XCTAssertTrue(alpha.waitForExistence(timeout: 10))
        alpha.hover()
        XCTAssertTrue(reopened.buttons["Today"].waitForNonExistence(timeout: 3), "o cartão não volta ao mural")
    }

    /// "Mover para o mural" tira o cartão de dentro da pasta e o devolve ao mural.
    @MainActor
    func testMovingCardOutOfFolderReturnsItToBoard() throws {
        let app = launch()
        let folder = app.buttons["The Cottage"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 10))
        folder.click()
        let back = app.buttons["Voltar"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))

        let thoughts = app.buttons["Thoughts"].firstMatch
        XCTAssertTrue(thoughts.waitForExistence(timeout: 5))
        thoughts.rightClick()
        app.menuItems["Mover para o mural"].click()
        XCTAssertTrue(thoughts.waitForNonExistence(timeout: 5), "o cartão sai da pasta")

        back.click()
        XCTAssertTrue(back.waitForNonExistence(timeout: 5))
        app.buttons["Alpha"].firstMatch.hover()
        XCTAssertTrue(app.buttons["Thoughts"].firstMatch.waitForExistence(timeout: 5), "o cartão aparece no mural")
    }

    /// O menu de contexto "Mover para a pasta" guarda um cartão solto na pasta escolhida, sem arrastar.
    @MainActor
    func testContextMenuStoresCardInFolder() throws {
        let app = launch()
        let alpha = app.buttons["Alpha"].firstMatch
        XCTAssertTrue(alpha.waitForExistence(timeout: 10))
        alpha.rightClick()
        app.menuItems["Mover para a pasta"].hover()
        app.menuItems["ACME Premises"].click()

        // Afasta o ponteiro das pastas, para nenhuma prévia mostrar o cartão guardado.
        app.buttons["Today"].firstMatch.hover()
        XCTAssertTrue(app.buttons["Alpha"].waitForNonExistence(timeout: 3), "o cartão guardado sai do mural")

        app.buttons["ACME Premises"].firstMatch.click()
        XCTAssertTrue(app.buttons["Voltar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Alpha"].waitForExistence(timeout: 5), "o cartão aparece dentro da pasta")
    }

    @MainActor
    func testChecklistEntryToggles() throws {
        let app = launch()
        let list = app.buttons["Things I need"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        list.click()

        // A linha da lista é exposta como caixa de seleção (traço de alternância).
        let entry = app.checkBoxes["Sofa / sectional"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertEqual(entry.value as? String, "Não marcado")
        entry.click()
        XCTAssertEqual(entry.value as? String, "Marcado")
        XCTAssertTrue(app.staticTexts["1 de 28 marcados"].exists)
    }

    @MainActor
    func testPastedTextBecomesStickyAndSurvivesRelaunch() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["The Cottage"].firstMatch.waitForExistence(timeout: 10))

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("Comprar tinta azul", forType: .string)
        app.typeKey("v", modifierFlags: .command)
        // Texto solto pergunta o tipo; texto curto já vem com Sticker sugerido (Return).
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "⌘V com texto deveria abrir o popup")
        XCTAssertTrue(sheet.buttons["Sticker"].exists)
        XCTAssertTrue(sheet.buttons["Card de texto"].exists)
        XCTAssertFalse(sheet.buttons["Lista"].exists, "texto sem marcadores não oferece lista")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["Comprar tinta azul"].waitForExistence(timeout: 5), "Return no popup deveria criar o post-it")

        app.terminate()
        let reopened = launch("-uiTestingKeep")
        XCTAssertTrue(
            reopened.buttons["Comprar tinta azul"].waitForExistence(timeout: 10), "o post-it colado deveria continuar após reabrir")
    }

    /// Colar como card de texto, abrir a nota e abrir um parágrafo dobrado no lugar.
    @MainActor
    func testPastedTextAsCardFoldsParagraphs() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["The Cottage"].firstMatch.waitForExistence(timeout: 10))

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("# Visita\n\nA visita é na segunda. Medir a parede norte.", forType: .string)
        app.typeKey("v", modifierFlags: .command)
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        sheet.buttons["Card de texto"].click()

        let card = app.buttons["Visita"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "o card de texto aparece no mural com o título do `#`")
        card.click()
        let paragraph = app.buttons["stretch-0"].firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 5), "o parágrafo de duas frases aparece dobrado")
        XCTAssertEqual(paragraph.value as? String, "Só a frase principal")
        paragraph.click()
        XCTAssertEqual(paragraph.value as? String, "Parágrafo inteiro")
    }

    /// Como o “Copiar Link” do Safari: o endereço e o nome da página no mesmo item da área de transferência.
    @MainActor
    func testPastedLinkBecomesLinkCardAndSurvivesRelaunch() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["The Cottage"].firstMatch.waitForExistence(timeout: 10))

        let entry = NSPasteboardItem()
        entry.setString("https://example.com/mural-teste", forType: .URL)
        entry.setString("Página de teste Mural", forType: NSPasteboard.PasteboardType("public.url-name"))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([entry])
        app.typeKey("v", modifierFlags: .command)
        XCTAssertTrue(
            app.buttons["Página de teste Mural"].waitForExistence(timeout: 5), "⌘V com um endereço deveria criar um cartão de link")

        app.terminate()
        let reopened = launch("-uiTestingKeep")
        XCTAssertTrue(
            reopened.buttons["Página de teste Mural"].waitForExistence(timeout: 10),
            "o cartão de link colado deveria continuar após reabrir")
    }

    @MainActor
    func testPastedImageFileOpensWithMetadata() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["The Cottage"].firstMatch.waitForExistence(timeout: 10))

        let url = try Self.makePNG(named: "foto-teste")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        app.typeKey("v", modifierFlags: .command)

        let card = app.buttons["foto-teste"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "⌘V com arquivo de imagem deveria criar um cartão")
        card.click()
        // Rótulo e valor formam um só elemento de acessibilidade: "RESOLUTION, 40 × 30".
        let resolution = app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "40 × 30")).firstMatch
        XCTAssertTrue(resolution.waitForExistence(timeout: 5), "detalhe da imagem mostra a resolução lida do arquivo")
    }

    /// Colar com uma pasta aberta põe o conteúdo dentro dela; com notas e imagem
    /// juntas, a coleção mostra as duas grades lado a lado.
    @MainActor
    func testPastingImageIntoFolderShowsBothColumns() throws {
        let app = launch()
        let folder = app.buttons["The Cottage"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 10))
        folder.click()
        XCTAssertTrue(app.buttons["Voltar"].waitForExistence(timeout: 5))

        let url = try Self.makePNG(named: "foto-na-pasta")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        app.typeKey("v", modifierFlags: .command)

        XCTAssertTrue(app.buttons["foto-na-pasta"].waitForExistence(timeout: 5), "a imagem colada entra na pasta aberta")
        XCTAssertTrue(app.buttons["Meeting Notes – Andrea and Jasmine"].exists, "as notas continuam ao lado")
        XCTAssertEqual(app.state, .runningForeground, "o app continua aberto")
    }

    /// Seletor "Mural: nome": cria o mural B, volta ao rascunho pelo seletor sem abrir outra
    /// janela, e o conteúdo do rascunho continua no mesmo lugar.
    @MainActor
    func testSwitcherCreatesBoardAndReturnsWithoutDuplicatingWindows() throws {
        let app = launch()
        let cottage = app.buttons["The Cottage"].firstMatch
        XCTAssertTrue(cottage.waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.buttons["Arquivos…"].firstMatch.waitForExistence(timeout: 5),
            "o botão de arquivos da barra inferior tem nome visível")
        let draftWindow = app.windows.containing(.button, identifier: "The Cottage").firstMatch
        let before = CGPoint(x: cottage.frame.minX - draftWindow.frame.minX, y: cottage.frame.minY - draftWindow.frame.minY)

        let switcher = app.descendants(matching: .any)["board-switcher"].firstMatch
        XCTAssertTrue(switcher.waitForExistence(timeout: 5), "o seletor Mural: nome deveria estar na barra")
        switcher.click()
        let newBoard = app.descendants(matching: .any)["switcher-new-board"].firstMatch
        XCTAssertTrue(newBoard.waitForExistence(timeout: 5))
        newBoard.click()
        let name = app.textFields["Nome do mural"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        name.typeText("Mural B\r")

        // O seletor expõe o nome no título do botão de menu.
        let switcherB = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND title == %@", "board-switcher", "Mural: Mural B"))
            .firstMatch
        XCTAssertTrue(switcherB.waitForExistence(timeout: 10), "o mural B deveria abrir numa janela própria")
        let windowCount = app.windows.count

        switcherB.click()
        let draftEntry = app.descendants(matching: .any)["switcher-entry-Rascunho de exemplo"].firstMatch
        XCTAssertTrue(draftEntry.waitForExistence(timeout: 5), "o seletor lista o rascunho")
        draftEntry.click()

        XCTAssertTrue(cottage.waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.count, windowCount, "escolher um mural já aberto não cria outra janela")
        let after = CGPoint(x: cottage.frame.minX - draftWindow.frame.minX, y: cottage.frame.minY - draftWindow.frame.minY)
        XCTAssertEqual(after.x, before.x, accuracy: 4, "o rascunho volta igual")
        XCTAssertEqual(after.y, before.y, accuracy: 4, "o rascunho volta igual")
    }

    /// Fechar a janela logo depois de colar (antes do salvamento automático) não perde o
    /// conteúdo: o fechamento real da janela grava, e a biblioteca reabre o mural do disco.
    @MainActor
    func testClosingWindowRightAfterPasteKeepsContent() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["The Cottage"].firstMatch.waitForExistence(timeout: 10))

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("Fechar sem perder", forType: .string)
        app.typeKey("v", modifierFlags: .command)
        // Texto solto passa pelo popup; Return aceita a sugestão (post-it, para texto curto).
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5), "⌘V com texto deveria abrir o popup")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["Fechar sem perder"].waitForExistence(timeout: 5))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(app.buttons["The Cottage"].waitForNonExistence(timeout: 5), "a janela do mural fecha")

        let draftEntry = app.descendants(matching: .any)["welcome-draft-entry"].firstMatch
        XCTAssertTrue(draftEntry.waitForExistence(timeout: 10), "a biblioteca continua aberta")
        // Um clique abre; com as janelas em abas, o segundo clique de um duplo clique cai na aba
        // "Murais" que surge sob o ponteiro e deixa o rascunho reaberto atrás.
        draftEntry.click()
        XCTAssertTrue(
            app.buttons["Fechar sem perder"].waitForExistence(timeout: 10),
            "o post-it colado antes de fechar deveria voltar")
    }

    /// Barra de criação → Pasta: dá o nome, a pasta abre vazia e fica no mural ao voltar.
    @MainActor
    func testCreationBarCreatesFolder() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["The Cottage"].firstMatch.waitForExistence(timeout: 10))
        let newFolder = app.buttons["Pasta"].firstMatch
        XCTAssertTrue(newFolder.waitForExistence(timeout: 5), "no mural, a barra de criação oferece Pasta")
        newFolder.click()
        let name = app.textFields["Nome da pasta"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        // Sem acento: a digitação sintética perdia letras depois do "ê" (tecla morta).
        name.typeText("Viagem\r")

        let back = app.buttons["Voltar"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "a pasta nova abre por cima do mural")
        XCTAssertFalse(app.buttons["Pasta"].exists, "dentro de uma pasta não se cria outra")
        back.click()
        XCTAssertTrue(app.buttons["Viagem"].firstMatch.waitForExistence(timeout: 5), "a pasta fica no mural")
    }

    /// ⌘-clique marca vários cartões; a barra do seletor apaga todos de uma vez, com confirmação.
    @MainActor
    func testCommandClickSelectsAndDeletesCards() throws {
        let app = launch()
        let first = app.buttons["Design Philosophy"].firstMatch
        let second = app.buttons["Alpha"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(second.exists)

        XCUIElement.perform(withKeyModifiers: .command) {
            first.click()
            second.click()
        }
        let bar = app.descendants(matching: .any)["selection-bar"].firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "com cartões marcados, a barra do seletor aparece")
        XCTAssertTrue(first.isSelected, "⌘-clique marca o cartão")
        XCTAssertTrue(second.isSelected)
        XCTAssertFalse(app.buttons["Voltar"].exists, "⌘-clique marca, não abre")

        app.buttons["Apagar…"].firstMatch.click()
        let confirm = app.buttons["Apagar"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "apagar vários pede confirmação")
        confirm.click()
        XCTAssertTrue(first.waitForNonExistence(timeout: 5), "os cartões marcados saem do mural")
        XCTAssertFalse(second.exists)
        XCTAssertTrue(app.buttons["The Cottage"].exists, "o resto do mural continua")
        XCTAssertFalse(bar.exists, "sem nada marcado, a barra de criação volta")
    }

    /// Visualizar › Organizar Mural (⌃⌘O) arruma os cartões soltos sem sobreposição; ⌘Z devolve.
    @MainActor
    func testOrganizeBoardTilesCardsAndUndoes() throws {
        let app = launch()
        let note = app.buttons["Design Philosophy"].firstMatch
        let sticky = app.buttons["The idea is this"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        XCTAssertTrue(sticky.exists)
        XCTAssertTrue(note.frame.intersects(sticky.frame), "no exemplo, o sticker cobre parte da nota")
        XCTAssertTrue(app.menuItems["Organizar Mural"].exists, "o menu Visualizar oferece Organizar Mural")

        app.typeKey("o", modifierFlags: [.command, .control])
        let separated = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !note.frame.intersects(sticky.frame) }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [separated], timeout: 5), .completed, "organizado, o sticker sai de cima da nota")
        // Títulos que só existem soltos no mural (os de dentro das pastas podem aparecer na prévia).
        let titles = [
            "Design Philosophy", "Alpha", "44th Street", "ACME Premises", "Today", "Running list of stuff",
            "The idea is this", "Don't forget",
        ]
        let frames = titles.map { app.buttons[$0].firstMatch.frame }
        for (index, frame) in frames.enumerated() {
            for other in frames.indices where other > index {
                XCTAssertFalse(frame.intersects(frames[other]), "\(titles[index]) cobre \(titles[other])")
            }
        }
        // Evidência visual do mosaico, guardada no .xcresult mesmo quando o teste passa.
        let organized = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        organized.name = "Mural organizado"
        organized.lifetime = .keepAlways
        add(organized)

        app.typeKey("z", modifierFlags: .command)
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in note.frame.intersects(sticky.frame) }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed, "⌘Z devolve os cartões")
    }

    /// Arrasta o elemento a partir do centro: segura um instante e solta `dx`, `dy` pontos adiante.
    @MainActor
    private func drag(_ element: XCUIElement, dx: CGFloat, dy: CGFloat) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.click(forDuration: 0.3, thenDragTo: start.withOffset(CGVector(dx: dx, dy: dy)))
    }

    /// PNG 40×30 gerado no teste: nenhum arquivo de imagem é versionado.
    private static func makePNG(named name: String) throws -> URL {
        let rep = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 30, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for x in 0..<40 {
            for y in 0..<30 {
                rep.setColor(x < 20 ? .systemOrange : .systemIndigo, atX: x, y: y)
            }
        }
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).png")
        try data.write(to: url)
        return url
    }
}
