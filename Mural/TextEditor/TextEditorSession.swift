import Observation

/// O estado do editor de texto que vale para o app inteiro: o documento, se a janela está aberta e o que fazer ao pedir para colar
/// no mural.
///
/// Um só (`shared`): reabrir a janela mostra o mesmo texto até ela ser fechada, e o texto não é guardado em disco.
///
/// Contrato de quem fecha ou usa o editor:
/// - Fechar a janela com texto pede confirmação (`dismissalConfirmationDialog`, que também aparece no fechamento por código, e
///   sair do app também pergunta, `shouldAskBeforeQuit`). Quem fechar a janela por código precisa limpar o documento antes
///   (`document.clear()`), ou a pergunta aparece.
/// - Depois de colar no mural com sucesso, o editor continua aberto com o texto (decisão de uso): quem cola não limpa nem fecha.
/// - "Colar no mural…" só vale com `onPasteRequested` ligado, para o botão nunca ficar sem efeito.
@MainActor @Observable
final class TextEditorSession {
    /// O editor do app.
    static let shared = TextEditorSession()

    /// O documento. Um só por vez.
    let document = TextEditorDocument()

    /// A janela do editor está aberta.
    var isOpen = false

    /// Chamado por "Colar no mural…" (⌘↩). Quem escolhe o mural é a galeria de destinos, ligada aqui depois; sem ele, colar fica
    /// desabilitado.
    @ObservationIgnored var onPasteRequested: (@MainActor () -> Void)?

    /// Há texto e a janela não pediu para sair: sair do app pergunta antes de perder o texto.
    var shouldAskBeforeQuit: Bool {
        !document.isEmpty
    }

    /// Dá para pedir "Colar no mural…": há texto e alguém para receber o pedido.
    var canRequestPaste: Bool {
        !document.isEmpty && onPasteRequested != nil
    }

    /// Abre o editor em branco, como o painel da barra de menus pede: se a janela está fechada, o documento começa vazio; se ela já
    /// está aberta com texto, o texto é da pessoa e fica (a janela só volta para a frente).
    func openBlank() {
        if !isOpen { document.clear() }
        TextEditorOpener.shared.open()
    }
}
