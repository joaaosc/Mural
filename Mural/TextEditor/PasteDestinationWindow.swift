import CoreGraphics

/// A cena da galeria "Colar no mural": uma janela de tamanho fixo, aberta por "Colar no mural…" do editor de texto
/// (`TextEditorSession.onPasteRequested`) e por `PasteDestinationOpener`.
enum PasteDestinationWindow {
    /// O identificador da cena (`Window(_, id:)`), usado para abri-la e fechá-la.
    static let sceneID = "paste-destination"
    /// O identificador de acessibilidade da janela, para os testes de interface.
    static let accessibilityIdentifier = "paste-destination-window"
    /// O tamanho fixo do conteúdo.
    static let size = CGSize(width: 820, height: 520)
}
