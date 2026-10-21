import MuralKit

/// Rascunho de uma nota ou de um post-it em edição. Só vai para o mural ao
/// concluir, ao sair da página ou ao fechar a janela.
struct NoteDraft: Equatable {
    var title: String
    /// Markdown, na nota; texto simples, no post-it.
    var text: String
    var color: StickyColor

    init(title: String = "", text: String = "", color: StickyColor = .yellow) {
        self.title = title
        self.text = text
        self.color = color
    }

    init(item: BoardItem) {
        self.init(title: item.title, text: item.text ?? "", color: item.stickyColor ?? .yellow)
    }
}
