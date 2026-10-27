import AppKit
import XCTest

/// O Live Share na janela de verdade, com a demonstração (`-uiTesting -liveShareDemo`, só nas compilações de desenvolvimento): duas
/// pessoas simuladas, sem chamada do FaceTime. As fotos da janela ficam no resultado do teste para a conferência a olho.
final class LiveShareUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLiveShareDemoShowsPeopleOnTheBoardAndInThePopover() throws {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-uiTesting", "-liveShareDemo"]
        app.launch()
        app.activate()

        // Um mural novo: o rascunho de exemplo não vai ao iCloud.
        let newBoard = app.buttons["new-board-button"].firstMatch
        XCTAssertTrue(newBoard.waitForExistence(timeout: 10), "o + fica na barra da janela")
        newBoard.click()
        let name = app.textFields["Nome do mural"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        name.typeText("Ao vivo\r")
        let tab = app.buttons.matching(identifier: "board-tab").matching(NSPredicate(format: "label == %@", "Ao vivo")).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "o mural novo abre numa aba")

        // Um post-it, para o Caio arrastar e aparecer editando.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("Plano da semana", forType: .string)
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).click()
        app.typeKey("v", modifierFlags: .command)
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5), "⌘V com texto pergunta o tipo")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["Plano da semana"].waitForExistence(timeout: 5), "o post-it entra no mural")

        // Convida o convidado de teste: o popover passa a oferecer o Live Share.
        let share = app.buttons["share-button"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.click()
        let invite = app.buttons["share-invite-test-guest-button"].firstMatch
        XCTAssertTrue(invite.waitForExistence(timeout: 5))
        invite.click()
        let start = app.buttons["share-live-button"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10), "com alguém convidado, o popover oferece o Live Share")
        attach(XCUIScreen.main.screenshot(), "1 Popover pronto")
        start.click()

        // A demonstração põe a Bia (ponteiro dando voltas) e o Caio (arrastando o post-it, editando) no mural.
        Thread.sleep(forTimeInterval: 1.0)
        attach(app.windows.firstMatch.screenshot(), "2 Mural ao vivo")
        Thread.sleep(forTimeInterval: 0.7)
        attach(app.windows.firstMatch.screenshot(), "3 Mural ao vivo, depois")

        share.click()
        let leave = app.buttons["share-live-leave-button"].firstMatch
        XCTAssertTrue(leave.waitForExistence(timeout: 5), "ao vivo, o popover mostra quem está e o botão de sair")
        attach(XCUIScreen.main.screenshot(), "4 Popover ao vivo")
        leave.click()
        Thread.sleep(forTimeInterval: 0.5)
        attach(app.windows.firstMatch.screenshot(), "5 Depois de sair")
    }

    private func attach(_ screenshot: XCUIScreenshot, _ name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
