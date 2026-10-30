import AppKit
import Testing

@testable import Mural

@MainActor
@Suite("Sessão do editor de texto")
struct TextEditorSessionTests {
    @Test("Sem ação registrada, abrir o editor devolve falso")
    func openerWithoutAction() {
        #expect(TextEditorOpener().open() == false)
    }

    @Test("Sair do app pergunta só com texto no documento")
    func quitAsksOnlyWithText() {
        let session = TextEditorSession()
        #expect(!session.shouldAskBeforeQuit)
        session.document.text = "  \n"
        #expect(!session.shouldAskBeforeQuit, "só espaços não é texto")
        session.document.text = "Rascunho"
        #expect(session.shouldAskBeforeQuit)
        session.document.clear()
        #expect(!session.shouldAskBeforeQuit)
    }

    @Test("Colar no mural só vale com texto e com quem receba o pedido")
    func pasteNeedsTextAndAReceiver() {
        let session = TextEditorSession()
        session.document.text = "Rascunho"
        #expect(!session.canRequestPaste, "sem a galeria ligada o botão fica desligado")
        session.onPasteRequested = {}
        #expect(session.canRequestPaste)
        session.document.clear()
        #expect(!session.canRequestPaste)
    }

    @Test("O painel abre em branco com a janela fechada, mas não apaga o texto de uma janela aberta")
    func openBlankKeepsTextOfAnOpenWindow() {
        let session = TextEditorSession()
        session.document.text = "Sobrou"
        session.openBlank()
        #expect(session.document.isEmpty, "janela fechada: começa em branco")

        session.document.text = "Da pessoa"
        session.isOpen = true
        session.openBlank()
        #expect(session.document.text == "Da pessoa")
    }

    @Test("O delegado do app pergunta antes de sair com texto no editor e deixa sair se a pessoa descarta")
    func delegateAsksBeforeQuitting() {
        let delegate = MuralAppDelegate()
        let session = TextEditorSession()
        session.document.text = "Rascunho"
        delegate.textEditor = session
        var asked = 0
        delegate.confirmQuitWithEditorText = {
            asked += 1
            return false
        }
        #expect(delegate.applicationShouldTerminate(.shared) == .terminateCancel)
        #expect(asked == 1)

        delegate.confirmQuitWithEditorText = { true }
        delegate.openSessions = OpenBoardSessions()
        #expect(delegate.applicationShouldTerminate(.shared) == .terminateNow)

        session.document.clear()
        delegate.confirmQuitWithEditorText = {
            Issue.record("não deveria perguntar sem texto")
            return true
        }
        #expect(delegate.applicationShouldTerminate(.shared) == .terminateNow)
    }
}
