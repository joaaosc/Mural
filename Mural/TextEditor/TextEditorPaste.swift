import MuralKit

/// O que o editor leu da área de transferência ao colar.
enum TextEditorPaste: Sendable {
    case contacts([ContactDraft])
    case music([MusicDraft])
    case links([LinkDraft])
    /// Imagens (e o texto que veio entre elas), na ordem original.
    case images([NoteImagePaste.Piece])
    case text(String)
    case nothing

    /// Os cartões embutidos que o colar vira: um por contato, música ou link; vazio para imagens e texto.
    ///
    /// O contato embutido não leva a foto (ela é local e o cartão embutido não tem arquivo), e a música não leva a capa. O link
    /// embutido começa com a prévia por buscar (`LinkPreviewState.pending`).
    var embeddedCards: [EmbeddedCard] {
        switch self {
        case .contacts(let drafts):
            drafts.map { .contact($0.snapshot) }
        case .music(let drafts):
            drafts.map { .music($0.snapshot) }
        case .links(let drafts):
            drafts.map {
                .link(
                    LinkInfo(
                        url: $0.url, pageTitle: $0.title, summary: $0.summary, remoteImageURL: $0.imageURL, preview: .pending))
            }
        case .images, .text, .nothing:
            []
        }
    }
}
