import MuralKit

extension ItemKind {
    /// Nome do tipo nos botões de criar e no popup de colar.
    var creationTitle: String {
        switch self {
        case .text: "Card de texto"
        case .sticky: "Sticker"
        case .checklist: "Lista"
        case .image: "Imagem"
        case .video: "Vídeo"
        case .pdf: "PDF"
        case .folder: "Pasta"
        }
    }

    /// Símbolo do tipo nos botões de criar e no popup de colar.
    var creationSymbol: String {
        switch self {
        case .text: "text.document"
        case .sticky: "square.text.square"
        case .checklist: "checklist"
        case .image: "photo"
        case .video: "film"
        case .pdf: "richtext.page"
        case .folder: "folder"
        }
    }
}
