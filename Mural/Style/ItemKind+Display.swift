import Foundation
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
        case .link: ("link", "links")
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

    /// Aviso mostrado antes de apagar um cartão.
    static func deleteWarning(for item: BoardItem, childCount: Int) -> String {
        guard item.kind == .folder else {
            return "O cartão e o arquivo guardado pelo Mural serão removidos. O arquivo original não é tocado."
        }
        return switch childCount {
        case 0: "A pasta vazia será removida."
        case 1: "A pasta e o item dentro dela serão removidos."
        default: "A pasta e os \(childCount) itens dentro dela serão removidos."
        }
    }

    /// Aviso mostrado antes de apagar vários cartões marcados: conta o que as pastas levam junto.
    static func deleteWarning(forSelection items: [BoardItem], childCount: (UUID) -> Int) -> String {
        let files = "Os arquivos guardados pelo Mural serão removidos; os originais não são tocados."
        let folders = items.filter { $0.kind == .folder }
        guard !folders.isEmpty else { return files }
        let inside = folders.reduce(0) { $0 + childCount($1.id) }
        let marked = ItemKind.folder.count(folders.count)
        guard inside > 0 else { return "Inclui \(marked) sem nada dentro. \(files)" }
        let contents = inside == 1 ? "1 item" : "\(inside) itens"
        return "Inclui \(marked) com \(contents) dentro, que também serão removidos. \(files)"
    }
}
