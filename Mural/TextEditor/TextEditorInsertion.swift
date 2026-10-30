import MuralKit

/// O que o botão Inserir do editor oferece: as imagens, cada tipo de cartão que uma nota pode embutir e a busca no Finder. Vale para a
/// barra e para o menu Editar, na mesma ordem.
enum TextEditorInsertion: String, CaseIterable, Identifiable {
    case photos
    case music
    case reminder
    case link
    case contact
    case finder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photos: "Fotos…"
        case .music: "Música…"
        case .reminder: "Lembrete…"
        case .link: "Link…"
        case .contact: "Contato…"
        case .finder: "Procurar no Finder…"
        }
    }

    var symbolName: String {
        switch self {
        case .photos: ItemKind.image.creationSymbol
        case .music: ItemKind.music.creationSymbol
        case .reminder: ItemKind.reminder.creationSymbol
        case .link: ItemKind.link.creationSymbol
        case .contact: ItemKind.contact.creationSymbol
        case .finder: "finder"
        }
    }

    /// Abre uma folha do próprio editor; os outros usam um painel do sistema.
    var usesSheet: Bool {
        switch self {
        case .music, .reminder, .link: true
        case .photos, .contact, .finder: false
        }
    }
}
