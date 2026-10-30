import Foundation

/// Os jeitos de guardar um texto colado.
public enum PasteKind: Hashable, Sendable {
    /// Post-it.
    case sticky
    /// Nota.
    case text
    /// Lista de tarefas.
    case checklist
    /// Um cartão de link para cada endereço do texto.
    case links(count: Int)

    /// O tipo de cartão que sai; `nil` para os links, que são vários cartões de tipos já conhecidos.
    public var itemKind: ItemKind? {
        switch self {
        case .sticky: .sticky
        case .text: .text
        case .checklist: .checklist
        case .links: nil
        }
    }
}

/// O que sugerir ao colar um texto: o jeito marcado de antemão, os jeitos oferecidos e os que não valem, com o motivo.
public struct PasteKindSuggestion: Equatable, Sendable {
    /// O jeito marcado de antemão; nunca um dos `unavailable`.
    public var suggested: PasteKind
    /// Os jeitos oferecidos, na ordem em que aparecem, os que não valem inclusive (para mostrar desligados). Vazio quando o texto
    /// está em branco.
    public var options: [PasteKind]
    /// Os jeitos de `options` que não valem para este texto, com o motivo em uma frase.
    public var unavailable: [PasteKind: String]

    public init(suggested: PasteKind, options: [PasteKind], unavailable: [PasteKind: String] = [:]) {
        self.suggested = suggested
        self.options = options
        self.unavailable = unavailable
    }
}

/// Decide como sugerir o jeito de guardar um texto colado.
///
/// Em ordem: endereços (um por linha) sugerem links; texto com cara de lista (`ChecklistParser.looksLikeChecklist`, que conta
/// marcadores como `- `, `1. ` e `[ ]`, em metade ou mais das linhas) sugere lista; o que cabe num post-it (`ContentClassifier.stickyLimit`) sugere post-it; o
/// resto, nota. Texto com cartões embutidos ou imagens não pode virar post-it, lista nem links, que perderiam essas partes: a
/// sugestão cai na nota.
///
/// Uma exceção à regra de que a sugestão está entre as opções: o texto em branco devolve `suggested: .text` com `options` vazio.
public enum PasteKindDetector {
    static let stickyVeto = "Sticker não guarda imagens nem cartões"
    static let linksVeto = "Cartões de link não guardam imagens nem cartões"
    static let checklistVeto = "Lista não guarda imagens nem cartões"

    /// - Parameters:
    ///   - text: o texto colado.
    ///   - hasEmbeds: o texto tem cartões embutidos (`mural-card:`).
    ///   - hasImages: o texto tem imagens coladas.
    public static func detect(text: String, hasEmbeds: Bool, hasImages: Bool) -> PasteKindSuggestion {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return PasteKindSuggestion(suggested: .text, options: []) }

        var suggested: PasteKind
        let options: [PasteKind]
        let urls = WebLink.urls(inText: trimmed)
        if !urls.isEmpty {
            suggested = .links(count: urls.count)
            options = [suggested, .text, .sticky]
        } else if ChecklistParser.looksLikeChecklist(trimmed) {
            suggested = .checklist
            options = [.checklist, .text, .sticky]
        } else if trimmed.count <= ContentClassifier.stickyLimit {
            suggested = .sticky
            options = [.sticky, .text]
        } else {
            suggested = .text
            options = [.text, .sticky]
        }

        var unavailable: [PasteKind: String] = [:]
        if hasEmbeds || hasImages {
            for kind in options {
                switch kind {
                case .sticky: unavailable[kind] = stickyVeto
                case .links: unavailable[kind] = linksVeto
                case .checklist: unavailable[kind] = checklistVeto
                case .text: break
                }
            }
        }
        if unavailable[suggested] != nil { suggested = .text }
        return PasteKindSuggestion(suggested: suggested, options: options, unavailable: unavailable)
    }
}
