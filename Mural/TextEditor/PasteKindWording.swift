import MuralKit

/// Os textos e símbolos dos jeitos de colar o texto do editor. Funções puras, para testar sem tela.
enum PasteKindWording {
    /// "Sticker", "Card de texto", "Lista", "Link" ou "3 links".
    static func title(of kind: PasteKind) -> String {
        switch kind {
        case .links(let count): count > 1 ? "\(count) links" : "Link"
        case .sticky, .text, .checklist: kind.itemKind?.creationTitle ?? ""
        }
    }

    /// O símbolo do jeito de colar.
    static func symbol(of kind: PasteKind) -> String {
        switch kind {
        case .links: ItemKind.link.creationSymbol
        case .sticky, .text, .checklist: kind.itemKind?.creationSymbol ?? "doc"
        }
    }

    /// A frase da linha desligada, ou "em <mural>" na escolhida.
    static func summary(unavailable reason: String?, board: String) -> String {
        reason ?? "em \(board)"
    }
}
