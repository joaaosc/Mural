import MuralKit

extension ItemKind {
    /// Nome no singular e no plural, para contagens como "2 imagens, 1 vídeo".
    private var names: (singular: String, plural: String) {
        switch self {
        case .image: ("imagem", "imagens")
        case .video: ("vídeo", "vídeos")
        case .pdf: ("PDF", "PDFs")
        case .text: ("nota", "notas")
        case .checklist: ("lista", "listas")
        case .sticky: ("post-it", "post-its")
        case .folder: ("pasta", "pastas")
        }
    }

    func count(_ quantity: Int) -> String {
        "\(quantity) \(quantity == 1 ? names.singular : names.plural)"
    }

    /// Resumo do conteúdo de uma pasta, na ordem dos tipos ("2 imagens, 1 nota").
    static func summary(of items: [BoardItem]) -> String {
        guard !items.isEmpty else { return "Vazia" }
        return
            allCases
            .compactMap { kind in
                let quantity = items.count { $0.kind == kind }
                return quantity > 0 ? kind.count(quantity) : nil
            }
            .joined(separator: ", ")
    }
}
