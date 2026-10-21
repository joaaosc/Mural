/// Negrito (`**`) e itálico (`*`) aplicados ou retirados em volta da seleção do
/// editor de Markdown, como ⌘B e ⌘I fazem num editor de texto.
///
/// As posições são contadas em `Character`, para não depender dos índices de uma
/// `String` que muda. A regra olha a sequência de `*` logo antes e logo depois da
/// seleção: com 2 há negrito, com 1 há itálico, com 3 há os dois. Se a seleção
/// inclui os próprios asteriscos, eles contam como se estivessem do lado de fora.
public enum MarkdownEmphasis: Sendable, CaseIterable {
    case bold
    case italic

    var width: Int {
        switch self {
        case .bold: 2
        case .italic: 1
        }
    }

    /// Esta ênfase já está aplicada quando a sequência de `*` em volta tem este tamanho.
    func isApplied(run: Int) -> Bool {
        switch self {
        case .bold: run == 2 || run >= 3
        case .italic: run == 1 || run >= 3
        }
    }

    /// Aplica a ênfase, ou retira se ela já envolve a seleção. Devolve o texto novo e a
    /// seleção sobre o mesmo conteúdo (ou o cursor entre os asteriscos, se a seleção era vazia).
    public func toggle(in text: String, selection: Range<Int>) -> (text: String, selection: Range<Int>) {
        var characters = Array(text)
        let lower = min(max(selection.lowerBound, 0), characters.count)
        let upper = min(max(selection.upperBound, lower), characters.count)
        var range = lower..<upper

        // Asteriscos selecionados junto com o texto passam para o lado de fora.
        let leadingInside = characters[range].prefix { $0 == "*" }.count
        let trailingInside = characters[range].reversed().prefix { $0 == "*" }.count
        let inside = min(leadingInside, trailingInside)
        if inside > 0, range.count > leadingInside + trailingInside {
            range = (range.lowerBound + inside)..<(range.upperBound - inside)
        }

        let before = characters[..<range.lowerBound].reversed().prefix { $0 == "*" }.count
        let after = characters[range.upperBound...].prefix { $0 == "*" }.count
        let marker = Array(repeating: Character("*"), count: width)

        if isApplied(run: min(before, after)) {
            characters.removeSubrange(range.upperBound..<(range.upperBound + width))
            characters.removeSubrange((range.lowerBound - width)..<range.lowerBound)
            return (String(characters), (range.lowerBound - width)..<(range.upperBound - width))
        }
        characters.insert(contentsOf: marker, at: range.upperBound)
        characters.insert(contentsOf: marker, at: range.lowerBound)
        return (String(characters), (range.lowerBound + width)..<(range.upperBound + width))
    }
}
