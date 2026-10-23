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

        // Sem abas, a janela abre com a barra lateral de murais à mostra.
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
        // Sem abas, a barra lateral abre sozinha; fechada pelo botão dela, o mural volta a ocupar a janela
        // inteira, que é o que os testes de posição e zoom medem.
        let sidebarButton = app.buttons["murals-sidebar-button"].firstMatch
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: 5), "o botão da barra lateral fica ao lado dos semáforos")
        sidebarButton.click()
        XCTAssertTrue(draftEntry.waitForNonExistence(timeout: 5), "o botão fecha a barra lateral")
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
        // Pastas também guardam pastas: o filtro existe aqui, mas começa desligado.
        XCTAssertFalse(app.buttons["Pastas"].firstMatch.isSelected, "o filtro do mural não entra na pasta")
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

    /// O menu de contexto também leva uma pasta para dentro de outra, e a pasta guardada abre como pasta.
    @MainActor
    func testContextMenuMovesFolderIntoFolder() throws {
        let app = launch()
        let acme = app.buttons["ACME Premises"].firstMatch
        XCTAssertTrue(acme.waitForExistence(timeout: 10))
        acme.rightClick()
        app.menuItems["Mover para a pasta"].hover()
        app.menuItems["44th Street"].click()

        // Afasta o ponteiro das pastas, para nenhuma prévia mostrar a pasta guardada.
        app.buttons["Today"].firstMatch.hover()
        XCTAssertTrue(app.buttons["ACME Premises"].waitForNonExistence(timeout: 3), "a pasta guardada sai do mural")

        app.buttons["44th Street"].firstMatch.click()
        XCTAssertTrue(app.buttons["Voltar"].waitForExistence(timeout: 5))
        let inner = app.buttons["ACME Premises"].firstMatch
        XCTAssertTrue(inner.waitForExistence(timeout: 5), "a pasta aparece dentro da outra")
        inner.click()
        // A ACME do exemplo não tem nada dentro: abrir como pasta mostra o aviso de pasta vazia, que a
        // página de um item não tem.
        XCTAssertTrue(
            app.staticTexts["Pasta vazia"].firstMatch.waitForExistence(timeout: 5), "abre como pasta, não como página de item")
        XCTAssertTrue(app.buttons["Voltar"].exists)
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

        // O buscador falso dos testes de interface (sem rede) entrega o site "Exemplo", que o cartão expõe como
        // valor de acessibilidade. Vale se a prévia da primeira abertura foi gravada e se foi buscada de novo.
        let card = reopened.buttons["Página de teste Mural"]
        let fetched = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Exemplo"), object: card)
        XCTAssertEqual(
            XCTWaiter().wait(for: [fetched], timeout: 10), .completed,
            "a prévia do cartão de link deveria ser buscada pelo buscador falso e mostrar o site Exemplo")
    }

    /// Abrir o cartão de link mostra a página dentro do app. Nos testes de interface a página é um HTML local de
    /// exemplo, sem rede; "Página anterior" é a pílula do histórico da página, e "Voltar" sai do detalhe.
    @MainActor
    func testLinkDetailShowsLivePage() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["The Cottage"].firstMatch.waitForExistence(timeout: 10))

        let entry = NSPasteboardItem()
        entry.setString("https://example.com/mural-teste", forType: .URL)
        entry.setString("Página de teste Mural", forType: NSPasteboard.PasteboardType("public.url-name"))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([entry])
        app.typeKey("v", modifierFlags: .command)
        let card = app.buttons["Página de teste Mural"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "⌘V com um endereço deveria criar um cartão de link")

        card.click()
        let back = app.buttons["Voltar"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "abrir o cartão leva ao detalhe")
        XCTAssertTrue(app.buttons["Página anterior"].waitForExistence(timeout: 5), "a pílula do link tem o histórico da página")
        XCTAssertTrue(app.buttons["Abrir no navegador"].exists)

        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 10), "a página deveria aparecer dentro do app")
        let title = web.descendants(matching: .any).matching(
            NSPredicate(
                format: "label CONTAINS %@ OR value CONTAINS %@ OR title CONTAINS %@", "Página de exemplo", "Página de exemplo",
                "Página de exemplo")
        ).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "o texto da página local de exemplo deveria estar no conteúdo web")

        back.click()
        XCTAssertTrue(back.waitForNonExistence(timeout: 5), "Voltar sai do detalhe")
        XCTAssertTrue(app.buttons["Página de teste Mural"].waitForExistence(timeout: 5), "o cartão continua no mural")
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

    /// Abas como no Safari: "+" cria o mural B numa aba nova, a aba do rascunho volta com o conteúdo no mesmo
    /// lugar, tudo numa janela só, e ⌘W fecha a aba ativa.
    @MainActor
    func testTabsCreateBoardAndReturnWithoutDuplicatingWindows() throws {
        let app = launch()
        let cottage = app.buttons["The Cottage"].firstMatch
        XCTAssertTrue(cottage.waitForExistence(timeout: 10))
        let window = app.windows.containing(.button, identifier: "The Cottage").firstMatch
        let before = CGPoint(x: cottage.frame.minX - window.frame.minX, y: cottage.frame.minY - window.frame.minY)
        let tabs = app.buttons.matching(identifier: "board-tab")
        XCTAssertEqual(tabs.count, 1, "o rascunho abre numa aba")

        let newBoard = app.buttons["new-board-button"].firstMatch
        XCTAssertTrue(newBoard.waitForExistence(timeout: 5), "o + fica na barra da janela")
        newBoard.click()
        let name = app.textFields["Nome do mural"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        name.typeText("Mural B\r")

        let tabB = tabs.matching(NSPredicate(format: "label == %@", "Mural B")).firstMatch
        XCTAssertTrue(tabB.waitForExistence(timeout: 10), "o mural B abre numa aba nova")
        XCTAssertTrue(tabB.isSelected, "a aba nova fica ativa")
        XCTAssertEqual(tabs.count, 2)
        XCTAssertEqual(app.windows.count, 1, "abas, não janelas")
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = "Duas abas"
        shot.lifetime = .keepAlways
        add(shot)

        tabs.matching(NSPredicate(format: "label == %@", "Rascunho de exemplo")).firstMatch.click()
        XCTAssertTrue(cottage.waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.count, 1, "voltar à aba não cria outra janela")
        let after = CGPoint(x: cottage.frame.minX - window.frame.minX, y: cottage.frame.minY - window.frame.minY)
        XCTAssertEqual(after.x, before.x, accuracy: 4, "o rascunho volta igual")
        XCTAssertEqual(after.y, before.y, accuracy: 4, "o rascunho volta igual")

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(cottage.waitForNonExistence(timeout: 5), "⌘W fecha a aba do rascunho")
        XCTAssertEqual(tabs.count, 1)
        XCTAssertTrue(tabB.isSelected, "a aba que sobrou fica ativa")
    }

    /// Cor pelo menu do botão direito, como as tags do Finder: a fileira de cores aparece no menu, a cor
    /// escolhida vai para o cartão (lida pelo VoiceOver) e "Remover cor" a tira.
    @MainActor
    func testContextMenuColorsCard() throws {
        let app = launch()
        let cottage = app.buttons["The Cottage"].firstMatch
        XCTAssertTrue(cottage.waitForExistence(timeout: 10))
        cottage.rightClick()
        let red = app.menuItems["Vermelho"].firstMatch
        XCTAssertTrue(red.waitForExistence(timeout: 5), "a fileira de cores fica no menu do cartão")
        let menu = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        menu.name = "Menu com as cores"
        menu.lifetime = .keepAlways
        add(menu)
        red.click()
        XCTAssertEqual(cottage.value as? String, "Cor: Vermelho")
        let tinted = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        tinted.name = "Pasta vermelha"
        tinted.lifetime = .keepAlways
        add(tinted)

        cottage.rightClick()
        let remove = app.menuItems["Remover cor"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "com cor, o menu oferece Remover cor")
        remove.click()
        XCTAssertNotEqual(cottage.value as? String, "Cor: Vermelho")
    }

    /// Excluir mural pela barra lateral: o menu do botão direito pede confirmação, e o mural sai da lista e
    /// das abas (nos testes, apagado; no app, vai para o Lixo).
    @MainActor
    func testDeleteBoardFromSidebar() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["The Cottage"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["new-board-button"].firstMatch.click()
        let name = app.textFields["Nome do mural"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        name.typeText("Mural C\r")
        let tabC = app.buttons.matching(identifier: "board-tab")
            .matching(NSPredicate(format: "label == %@", "Mural C")).firstMatch
        XCTAssertTrue(tabC.waitForExistence(timeout: 10))

        app.buttons["murals-sidebar-button"].firstMatch.click()
        let entry = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "saved-board-entry-", "Mural C"))
            .firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "o mural novo aparece na barra lateral")
        entry.rightClick()
        app.menuItems["Excluir Mural…"].firstMatch.click()
        let confirm = app.buttons["Mover para o Lixo"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "excluir pede confirmação")
        confirm.click()

        XCTAssertTrue(entry.waitForNonExistence(timeout: 5), "o mural sai da barra lateral")
        XCTAssertFalse(tabC.exists, "e a aba dele fecha")
        XCTAssertTrue(app.buttons["The Cottage"].firstMatch.waitForExistence(timeout: 5), "a aba do rascunho assume")
    }

    /// Cor de uma vez nos cartões marcados com ⌘, pelas bolinhas da barra do seletor.
    @MainActor
    func testSelectionBarColorsMarkedCards() throws {
        let app = launch()
        let first = app.buttons["Design Philosophy"].firstMatch
        let second = app.buttons["Alpha"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCUIElement.perform(withKeyModifiers: .command) {
            first.click()
            second.click()
        }
        let colors = app.descendants(matching: .any)["selection-color"].firstMatch
        XCTAssertTrue(colors.waitForExistence(timeout: 5), "a barra do seletor oferece as cores")
        colors.buttons["Verde"].firstMatch.click()
        XCTAssertEqual(first.value as? String, "Cor: Verde")
        XCTAssertEqual(second.value as? String, "Cor: Verde")
        XCTAssertTrue(first.isSelected, "a marcação continua depois de dar a cor")
    }

    /// Filtro por cor: escolher uma cor na barra de filtros a destaca (o resto esmaece) e o botão diz qual.
    @MainActor
    func testColorFilterHighlightsChosenColor() throws {
        let app = launch()
        let cottage = app.buttons["The Cottage"].firstMatch
        XCTAssertTrue(cottage.waitForExistence(timeout: 10))
        cottage.rightClick()
        app.menuItems["Vermelho"].firstMatch.click()
        XCTAssertEqual(cottage.value as? String, "Cor: Vermelho")

        let filter = app.descendants(matching: .any)["color-filter"].firstMatch
        XCTAssertTrue(filter.waitForExistence(timeout: 5), "a barra de filtros tem o filtro de cor")
        filter.click()
        let red = app.menuItems["Vermelho"].firstMatch
        XCTAssertTrue(red.waitForExistence(timeout: 5))
        red.click()
        XCTAssertEqual(filter.value as? String, "Vermelho")
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = "Filtro vermelho"
        shot.lifetime = .keepAlways
        add(shot)
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
        XCTAssertTrue(app.buttons["The Cottage"].waitForNonExistence(timeout: 5), "⌘W fecha a última aba e a janela")

        // Como no Safari, o app continua aberto sem janela; ⇧⌘\ reabre com a lista de murais.
        app.typeKey("\\", modifierFlags: [.command, .shift])
        let draftEntry = app.descendants(matching: .any)["welcome-draft-entry"].firstMatch
        XCTAssertTrue(draftEntry.waitForExistence(timeout: 10), "a janela volta com a barra lateral")
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
        XCTAssertTrue(app.buttons["Pasta"].firstMatch.waitForExistence(timeout: 5), "dentro de uma pasta também se cria outra")

        app.buttons["Pasta"].firstMatch.click()
        let subName = app.textFields["Nome da pasta"].firstMatch
        XCTAssertTrue(subName.waitForExistence(timeout: 5))
        subName.click()
        subName.typeText("Sub\r")
        XCTAssertTrue(back.waitForExistence(timeout: 5), "a subpasta abre por cima da pasta")

        back.click()
        XCTAssertTrue(app.buttons["Sub"].firstMatch.waitForExistence(timeout: 5), "a subpasta fica dentro de Viagem")
        XCTAssertTrue(back.exists, "ainda estamos dentro de Viagem")
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
        // A barra sai com uma animação curta: espera em vez de conferir na hora.
        XCTAssertTrue(bar.waitForNonExistence(timeout: 3), "sem nada marcado, a barra de criação volta")
    }

    /// Shift + arrastar no vazio do mural marca os cartões que o retângulo cruza; dá para colorir e apagar de uma vez.
    @MainActor
    func testShiftDragSelectsColorsAndDeletesCards() throws {
        let app = launch()
        let window = app.windows.firstMatch
        let first = app.buttons["Design Philosophy"].firstMatch
        let second = app.buttons["Alpha"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(second.exists)

        // Do vão logo abaixo de "Alpha" até o meio de "Design Philosophy": cruza os dois e mais nenhum.
        let start = point(in: window, x: second.frame.midX, y: second.frame.maxY + 8)
        let end = point(in: window, x: first.frame.midX, y: first.frame.minY + 20)
        XCUIElement.perform(withKeyModifiers: .shift) {
            start.click(forDuration: 0.3, thenDragTo: end)
        }

        let bar = app.descendants(matching: .any)["selection-bar"].firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "o retângulo marca e a barra do seletor aparece")
        XCTAssertTrue(first.isSelected, "o retângulo cruzou o primeiro cartão")
        XCTAssertTrue(second.isSelected, "e o segundo")
        XCTAssertFalse(app.buttons["The Cottage"].firstMatch.isSelected, "a pasta fora do retângulo fica de fora")
        XCTAssertFalse(app.buttons["Voltar"].exists, "o arrasto não abre nenhum cartão")

        app.descendants(matching: .any)["selection-color"].firstMatch.buttons["Verde"].firstMatch.click()
        XCTAssertEqual(first.value as? String, "Cor: Verde")
        XCTAssertEqual(second.value as? String, "Cor: Verde")

        app.buttons["Apagar…"].firstMatch.click()
        let confirm = app.buttons["Apagar"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "apagar vários pede confirmação")
        confirm.click()
        XCTAssertTrue(first.waitForNonExistence(timeout: 5), "os cartões marcados saem do mural")
        XCTAssertFalse(second.exists)
        XCTAssertTrue(app.buttons["The Cottage"].exists, "o resto do mural continua")
    }

    /// Dentro da pasta, Shift + arrastar também marca: um retângulo pequeno que cruza só o cartão mais à esquerda.
    @MainActor
    func testShiftDragSelectsInsideFolder() throws {
        let app = launch()
        let window = app.windows.firstMatch
        let folder = app.buttons["The Cottage"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 10))
        folder.click()
        XCTAssertTrue(app.buttons["Voltar"].waitForExistence(timeout: 5))
        let titles = ["Meeting Notes – Andrea and Jasmine", "Thoughts", "Chairs and their Surroundings", "This week"]
        let cards = titles.map { app.buttons[$0].firstMatch }
        XCTAssertTrue(cards[0].waitForExistence(timeout: 5))
        // Espera a pasta terminar de abrir (os cartões param de se mover).
        Thread.sleep(forTimeInterval: 1)
        let leftmost = try XCTUnwrap(cards.filter(\.exists).min { $0.frame.minX < $1.frame.minX })

        let start = point(in: window, x: leftmost.frame.minX - 6, y: leftmost.frame.midY)
        let end = point(in: window, x: leftmost.frame.minX + 30, y: leftmost.frame.midY + 20)
        XCUIElement.perform(withKeyModifiers: .shift) {
            start.click(forDuration: 0.3, thenDragTo: end)
        }

        let bar = app.descendants(matching: .any)["selection-bar"].firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "o retângulo marca dentro da pasta")
        XCTAssertTrue(leftmost.isSelected, "o cartão cruzado fica marcado")
        XCTAssertEqual(cards.filter { $0.exists && $0.isSelected }.count, 1, "só ele")
        XCTAssertTrue(app.buttons["Voltar"].exists, "o arrasto não abre o cartão")
    }

    /// Dentro da pasta, arrastar um post-it o deixa onde foi solto, por cima das colunas, e o lugar volta ao reabrir o app.
    @MainActor
    func testDraggingStickyInsideFolderPlacesItFreely() throws {
        let app = launch()
        let folder = app.buttons["The Cottage"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 10))
        folder.click()
        XCTAssertTrue(app.buttons["Voltar"].waitForExistence(timeout: 5))
        let sticky = app.buttons["This week"].firstMatch
        XCTAssertTrue(sticky.waitForExistence(timeout: 5))
        // Espera a pasta terminar de abrir (os cartões param de se mover).
        Thread.sleep(forTimeInterval: 1)
        let before = sticky.frame

        drag(sticky, dx: -100, dy: 220)

        // Aberto, o post-it entra no título da janela ("The Cottage › This week").
        let opened = NSPredicate(format: "title CONTAINS %@", "This week")
        XCTAssertFalse(app.windows.matching(opened).firstMatch.waitForExistence(timeout: 1), "arrastar não abre o post-it")
        let moved = sticky.frame
        XCTAssertEqual(moved.minX - before.minX, -100, accuracy: 4)
        XCTAssertEqual(moved.minY - before.minY, 220, accuracy: 4)

        // A janela pode abrir em outro lugar da tela: compara a posição dentro dela.
        let window = app.windows.firstMatch.frame
        let relative = CGPoint(x: moved.minX - window.minX, y: moved.minY - window.minY)

        app.terminate()
        let reopened = launch("-uiTestingKeep")
        if !reopened.buttons["Voltar"].exists {
            reopened.buttons["The Cottage"].firstMatch.click()
            XCTAssertTrue(reopened.buttons["Voltar"].waitForExistence(timeout: 5))
        }
        let again = reopened.buttons["This week"].firstMatch
        XCTAssertTrue(again.waitForExistence(timeout: 5), "o post-it deveria continuar após reabrir")
        Thread.sleep(forTimeInterval: 1)
        let reopenedWindow = reopened.windows.firstMatch.frame
        XCTAssertEqual(again.frame.minX - reopenedWindow.minX, relative.x, accuracy: 4)
        XCTAssertEqual(again.frame.minY - reopenedWindow.minY, relative.y, accuracy: 4)

        again.click()
        XCTAssertTrue(
            reopened.windows.matching(opened).firstMatch.waitForExistence(timeout: 5), "o post-it solto continua abrindo")
    }

    /// Dentro da pasta, soltar um post-it sobre uma subpasta o guarda nela.
    @MainActor
    func testDroppingStickyOnSubfolderStoresIt() throws {
        let app = launch()
        // Prepara a subpasta: "44th Street" vai para dentro de "The Cottage", onde está o post-it "This week".
        let street = app.buttons["44th Street"].firstMatch
        XCTAssertTrue(street.waitForExistence(timeout: 10))
        street.rightClick()
        app.menuItems["Mover para a pasta"].hover()
        app.menuItems["The Cottage"].click()

        // Afasta o ponteiro das pastas, para nenhuma prévia mostrar a pasta guardada.
        app.buttons["Today"].firstMatch.hover()
        XCTAssertTrue(app.buttons["44th Street"].waitForNonExistence(timeout: 3), "a pasta guardada sai do mural")

        app.buttons["The Cottage"].firstMatch.click()
        XCTAssertTrue(app.buttons["Voltar"].waitForExistence(timeout: 5))
        let subfolder = app.buttons["44th Street"].firstMatch
        let sticky = app.buttons["This week"].firstMatch
        XCTAssertTrue(subfolder.waitForExistence(timeout: 5), "a pasta guardada aparece dentro da outra")
        XCTAssertTrue(sticky.waitForExistence(timeout: 5))
        // Espera a pasta terminar de abrir (os cartões param de se mover).
        Thread.sleep(forTimeInterval: 1)

        // Do centro do post-it até o centro da subpasta.
        drag(sticky, dx: subfolder.frame.midX - sticky.frame.midX, dy: subfolder.frame.midY - sticky.frame.midY)

        XCTAssertTrue(app.buttons["This week"].waitForNonExistence(timeout: 5), "o post-it entra na subpasta")

        subfolder.click()
        let inside = NSPredicate(format: "title CONTAINS %@", "44th Street")
        XCTAssertTrue(app.windows.matching(inside).firstMatch.waitForExistence(timeout: 5), "a janela mostra a subpasta")
        XCTAssertTrue(app.buttons["This week"].firstMatch.waitForExistence(timeout: 5), "o post-it aparece dentro da subpasta")
    }

    /// Botão direito num cartão › Renomear…: a folha começa com o nome atual e o cartão passa a mostrar o novo.
    @MainActor
    func testContextMenuRenamesCard() throws {
        let app = launch()
        let folder = app.buttons["44th Street"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 10))
        folder.rightClick()
        app.menuItems["Renomear…"].firstMatch.click()

        let name = app.textFields["Nome do cartão"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5), "renomear pede o nome")
        XCTAssertEqual(name.value as? String, "44th Street", "o campo começa com o nome atual")
        name.click()
        name.typeKey("a", modifierFlags: .command)
        name.typeText("Obra da Rua 44\r")

        XCTAssertTrue(
            app.buttons["Obra da Rua 44"].firstMatch.waitForExistence(timeout: 5), "o cartão da pasta mostra o nome novo")
        XCTAssertFalse(app.buttons["44th Street"].exists)
    }

    /// A legenda é independente do nome e pode ser adicionada pelo menu de qualquer cartão.
    @MainActor
    func testContextMenuAddsCaptionToCard() throws {
        let app = launch()
        let card = app.buttons["Running list of stuff"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.rightClick()
        app.menuItems["Adicionar legenda…"].firstMatch.click()

        let caption = app.textFields["Legenda"].firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 5), "adicionar legenda abre o campo")
        caption.click()
        caption.typeText("Contexto importante")
        app.buttons["Salvar"].firstMatch.click()

        XCTAssertTrue(
            app.staticTexts["Contexto importante"].firstMatch.waitForExistence(timeout: 5),
            "a legenda aparece no cartão sem substituir o nome")
        XCTAssertTrue(app.buttons["Running list of stuff"].exists)
    }

    /// Ponto da janela em coordenadas de tela (as de `frame`).
    @MainActor
    private func point(in window: XCUIElement, x: CGFloat, y: CGFloat) -> XCUICoordinate {
        window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: x - window.frame.minX, dy: y - window.frame.minY))
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

    /// Colar uma imagem no corpo de uma nota a cita no Markdown e a mostra na leitura.
    @MainActor
    func testPastingImageIntoNoteShowsIt() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["The Cottage"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Card de texto"].firstMatch.click()
        app.typeText("Nota com foto")
        app.typeKey(.return, modifierFlags: [])

        let body = app.textViews["Texto da nota em Markdown"]
        XCTAssertTrue(body.waitForExistence(timeout: 5), "o foco vai para o corpo da nota")

        let url = try Self.makePNG(named: "foto-na-nota")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(try Data(contentsOf: url), forType: .png)
        app.typeKey("v", modifierFlags: .command)

        let cited = NSPredicate(format: "value CONTAINS %@", "![Imagem colada](")
        expectation(for: cited, evaluatedWith: body)
        waitForExpectations(timeout: 5)

        app.typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(app.images["Imagem colada"].waitForExistence(timeout: 5), "a imagem colada aparece na leitura")
    }

    /// Com o cursor ainda no título, a imagem colada vai para o fim do corpo e o título fica como estava.
    @MainActor
    func testPastingImageInNoteTitleGoesToBody() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["The Cottage"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Card de texto"].firstMatch.click()
        let body = app.textViews["Texto da nota em Markdown"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        app.typeText("Nota com foto")
        // Compara com o que o campo recebeu, não com o digitado: o executor já mandou uma letra com ⌘ no meio.
        let title = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "Título")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let typed = try XCTUnwrap(title.value as? String)
        XCTAssertFalse(typed.isEmpty, "o cursor começa no título da nota nova")

        let url = try Self.makePNG(named: "foto-no-titulo")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(try Data(contentsOf: url), forType: .png)
        app.typeKey("v", modifierFlags: .command)

        let cited = NSPredicate(format: "value CONTAINS %@", "![Imagem colada](")
        expectation(for: cited, evaluatedWith: body)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(title.value as? String, typed, "o título não recebe a imagem")

        app.typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(app.images["Imagem colada"].waitForExistence(timeout: 5), "a imagem colada aparece na leitura")
    }

    /// O post-it novo abre com o cursor no texto: o que se digita entra nele.
    @MainActor
    func testNewStickyStartsWithCursorInText() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["The Cottage"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Sticker"].firstMatch.click()
        let text = app.textViews["Texto do post-it"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        app.typeText("Ligar para o pintor")

        let typed = NSPredicate(format: "value CONTAINS %@", "pintor")
        expectation(for: typed, evaluatedWith: text)
        waitForExpectations(timeout: 5)
    }

    /// Na página da nota, clicar na tarefa marca a caixa no texto, e a marca fica ao reabrir.
    @MainActor
    func testClickingTaskInNoteTogglesIt() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["The Cottage"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Card de texto"].firstMatch.click()
        let body = app.textViews["Texto da nota em Markdown"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        // Sem a letra "c" no que se digita: o executor de testes já mandou "c" com ⌘.
        app.typeText("Obra")
        app.typeKey(.return, modifierFlags: [])

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("- [ ] Pintar a porta\n- [x] Lixar o batente", forType: .string)
        app.typeKey("v", modifierFlags: .command)
        let pasted = NSPredicate(format: "value CONTAINS %@", "Pintar a porta")
        expectation(for: pasted, evaluatedWith: body)
        waitForExpectations(timeout: 5)
        app.typeKey(.return, modifierFlags: .command)

        let task = app.descendants(matching: .any)["stretch-task-0"]
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        XCTAssertEqual(task.value as? String, "A fazer")
        task.click()
        expectation(for: NSPredicate(format: "value == %@", "Feita"), evaluatedWith: task)
        waitForExpectations(timeout: 5)

        app.buttons["Voltar"].firstMatch.click()
        let reopened = app.buttons["Obra"].firstMatch
        XCTAssertTrue(reopened.waitForExistence(timeout: 5))
        reopened.click()
        let again = app.descendants(matching: .any)["stretch-task-0"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "value == %@", "Feita"), evaluatedWith: again)
        waitForExpectations(timeout: 5)
    }

    /// A folha de lembretes cria os cartões e a bolinha do cartão marca como concluído.
    @MainActor
    func testRemindersSheetAddsCardsAndToggles() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["The Cottage"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Lembretes…"].firstMatch.click()

        let list = app.staticTexts["Casa"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        list.click()
        let first = app.checkBoxes["Comprar pão"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.click()
        // "Pagar a luz" é concluído: aparece só com "Mostrar concluídos".
        app.checkBoxes["Mostrar concluídos"].click()
        let second = app.checkBoxes["Pagar a luz"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        second.click()
        app.buttons["Adicionar (2)"].click()

        XCTAssertTrue(app.buttons["Comprar pão"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Pagar a luz"].firstMatch.exists)

        let toggle = app.buttons["Marcar como concluído"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.click()
        XCTAssertTrue(app.buttons["Reabrir"].firstMatch.waitForExistence(timeout: 5))
    }

    /// ⌘V com um álbum no formato que o app Música põe ao arrastar (dados sintéticos) cria o cartão de música, que
    /// continua depois de reabrir. O botão sobre a capa toca pela ponte falsa dos testes de interface, sem Apple
    /// Music, e a página lista as faixas falsas.
    @MainActor
    func testPastedMusicBecomesMusicCardAndPlays() throws {
        let app = launch()
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
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Pausar"), object: toggle)
        XCTAssertEqual(XCTWaiter().wait(for: [playing], timeout: 5), .completed, "tocar deveria trocar o botão para Pausar")

        card.click()
        XCTAssertTrue(
            app.buttons["Tocar Faixa 1"].firstMatch.waitForExistence(timeout: 5), "a página deveria listar as faixas do álbum")

        app.terminate()
        let reopened = launch("-uiTestingKeep")
        XCTAssertTrue(
            reopened.buttons["Álbum de Teste"].firstMatch.waitForExistence(timeout: 10),
            "o cartão de música deveria continuar após reabrir")
    }
}
