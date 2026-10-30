import Foundation

/// O que o ícone do Mural na barra de menus mostra e diz: o desenho normal ou, com uma edição esperando para ser colada, um
/// lápis. Só decide os textos e o símbolo; quem os aplica ao item da barra é `MenuBarController`.
enum MenuBarIcon {
    /// O nome do símbolo do ícone.
    static func symbolName(isEditPending: Bool) -> String {
        isEditPending ? "square.and.pencil" : "rectangle.on.rectangle"
    }

    /// A descrição que o VoiceOver lê.
    static func accessibilityDescription(isEditPending: Bool) -> String {
        isEditPending ? "Mural — edição esperando para colar" : "Mural"
    }

    /// A dica de ferramenta ao parar o ponteiro sobre o ícone.
    static func toolTip(isEditPending: Bool) -> String {
        isEditPending ? "Mural: há uma edição esperando para ser colada" : "Mural"
    }
}
