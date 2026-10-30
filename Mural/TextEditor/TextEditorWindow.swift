/// A cena do editor de texto: uma janela auxiliar, com os controles padrão, aberta pelo menu, pelo painel da barra de menus e
/// por `TextEditorOpener`.
enum TextEditorWindow {
    /// O identificador da cena (`Window(_, id:)`), usado para abri-la.
    static let sceneID = "text-editor"
    /// O identificador de acessibilidade da janela, para os testes de interface.
    static let accessibilityIdentifier = "text-editor-window"
}
