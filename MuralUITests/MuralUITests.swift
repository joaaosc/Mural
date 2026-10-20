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
        app.launchArguments = [argument]
        app.launch()
        app.activate()
        return app
    }

    @MainActor
    func testBoardOpensFolderAndGoesBack() throws {
        let app = launch()
        let folder = app.buttons["The Cottage"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 10), "a pasta de exemplo deveria estar no mural")
        XCTAssertFalse(app.buttons["Voltar"].exists, "no mural não há para onde voltar")

        folder.click()
        let back = app.buttons["Voltar"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["CLIENT 001"].waitForExistence(timeout: 5), "etiqueta da coleção")
        XCTAssertTrue(app.buttons["Meeting Notes – Andrea and Jasmine"].exists, "cartão de dentro da pasta")

        back.click()
        XCTAssertTrue(back.waitForNonExistence(timeout: 5))
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
        XCTAssertTrue(app.buttons["Comprar tinta azul"].waitForExistence(timeout: 5), "⌘V com texto curto deveria criar um post-it")

        app.terminate()
        let reopened = launch("-uiTestingKeep")
        XCTAssertTrue(
            reopened.buttons["Comprar tinta azul"].waitForExistence(timeout: 10), "o post-it colado deveria continuar após reabrir")
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
