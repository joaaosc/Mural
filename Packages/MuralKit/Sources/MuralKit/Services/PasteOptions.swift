import Foundation

/// Uma maneira de colar o que está na área de transferência, como aparece no painel da barra de menus.
public struct PasteOption: Hashable, Sendable, Identifiable {
    public enum Action: Hashable, Sendable {
        /// Cola o conteúdo já lido, no tipo de cartão que ele tem.
        case asRead
        /// Cola o texto no tipo de cartão escolhido.
        case text(ItemKind)
        /// Ainda não se sabe o que é: lê a área de transferência na hora de colar.
        case read
        /// Abre o conteúdo num app para editar antes de colar; com uma edição pendente, volta a ela.
        case edit
        /// Descarta a edição pendente e volta ao que está copiado.
        case discardEdit
    }

    public let action: Action
    /// Tipo do cartão que sai; `nil` quando varia (arquivos) ou ainda não se sabe.
    public let kind: ItemKind?
    /// Quantos cartões entram; 0 quando ainda não se sabe.
    public let count: Int
    /// Opção marcada de antemão.
    public let isSuggested: Bool

    public init(action: Action, kind: ItemKind?, count: Int, isSuggested: Bool) {
        self.action = action
        self.kind = kind
        self.count = count
        self.isSuggested = isSuggested
    }

    /// Estável por ação: `asRead`, `read`, `edit`, `discardEdit` e `text-<tipo>` (por exemplo `text-sticky`).
    public var id: String {
        switch action {
        case .asRead: "asRead"
        case .read: "read"
        case .edit: "edit"
        case .discardEdit: "discardEdit"
        case .text(let kind): "text-\(kind.rawValue)"
        }
    }
}

/// As opções de colar que o painel oferece para o que está na área de transferência.
public enum PasteOptions {
    /// As opções na ordem em que aparecem; vazio quando não há o que colar. Uma opção única é sempre a sugerida.
    ///
    /// Texto usa `ContentClassifier.pasteChoice(forText:)`: uma opção por tipo de cartão possível, com a sugestão
    /// do classificador marcada. Texto só com espaços não conta.
    ///
    /// Com `allowsEditing`, o que tem tipo editável (``PasteEditKind``) e ao menos uma opção de colar ganha no fim a
    /// opção de editar antes de colar, nunca sugerida.
    /// - Parameters:
    ///   - kind: o que está na área de transferência.
    ///   - allowsEditing: inclui a opção de editar antes de colar.
    public static func options(for kind: ClipboardKind, allowsEditing: Bool = false) -> [PasteOption] {
        var options = pasteOptions(for: kind)
        if allowsEditing, PasteEditKind(kind) != nil, !options.isEmpty {
            options.append(PasteOption(action: .edit, kind: nil, count: 0, isSuggested: false))
        }
        return options
    }

    /// As opções de um conteúdo que já foi editado: as de colar dele, a de voltar a editar e a de descartar a edição.
    /// Sem opções de colar (texto em branco, por exemplo), ficam só as duas últimas.
    public static func options(forEdited kind: ClipboardKind) -> [PasteOption] {
        pasteOptions(for: kind) + [
            PasteOption(action: .edit, kind: nil, count: 0, isSuggested: false),
            PasteOption(action: .discardEdit, kind: nil, count: 0, isSuggested: false),
        ]
    }

    private static func pasteOptions(for kind: ClipboardKind) -> [PasteOption] {
        switch kind {
        case .nothing:
            return []
        case .links(let count):
            return [only(count > 0 ? .asRead : .read, kind: .link, count: count)]
        case .image:
            return [only(.asRead, kind: .image, count: 1)]
        case .pdf:
            return [only(.asRead, kind: .pdf, count: 1)]
        case .files(let count):
            return [only(count > 0 ? .asRead : .read, kind: nil, count: count)]
        case .music(let count):
            return [only(count > 0 ? .asRead : .read, kind: .music, count: count)]
        case .text(let text):
            guard let text else { return [only(.read, kind: nil, count: 0)] }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
            let choice = ContentClassifier.pasteChoice(forText: text)
            return choice.options.map {
                PasteOption(action: .text($0), kind: $0, count: 1, isSuggested: $0 == choice.suggested)
            }
        }
    }

    /// A posição da opção sugerida; sem nenhuma sugerida, a primeira.
    /// - Returns: `nil` se não houver opções.
    public static func suggestedIndex(in options: [PasteOption]) -> Int? {
        options.firstIndex { $0.isSuggested } ?? (options.isEmpty ? nil : 0)
    }

    /// A única opção de uma lista, que por isso é a sugerida. Contagem negativa vale como 0.
    private static func only(_ action: PasteOption.Action, kind: ItemKind?, count: Int) -> PasteOption {
        PasteOption(action: action, kind: kind, count: max(count, 0), isSuggested: true)
    }
}
