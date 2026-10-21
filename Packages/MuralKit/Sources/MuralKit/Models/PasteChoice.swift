/// O que perguntar ao colar texto solto: os tipos de cartão possíveis e o sugerido.
public struct PasteChoice: Equatable, Sendable {
    /// Tipo marcado de antemão (o que o classificador escolheria sozinho).
    public let suggested: ItemKind
    /// Lista só aparece quando o texto tem cara de lista.
    public let offersChecklist: Bool

    public init(suggested: ItemKind, offersChecklist: Bool) {
        self.suggested = suggested
        self.offersChecklist = offersChecklist
    }

    /// Opções na ordem dos botões.
    public var options: [ItemKind] {
        offersChecklist ? [.sticky, .text, .checklist] : [.sticky, .text]
    }
}
