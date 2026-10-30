import Foundation

/// Como o texto copiado é ajustado antes de virar cartão, no painel da barra de menus.
///
/// Cada formatação é uma função pura do texto: a mesma entrada dá sempre a mesma saída, e nenhuma lê a área de
/// transferência. A ordem dos casos é a ordem em que o painel os mostra, com o texto como foi copiado primeiro.
///
/// As que mexem em espaços tratam "\r\n" e "\r" como quebra de linha, e qualquer espaço (tabulação, espaço sem quebra)
/// como espaço. Caracteres invisíveis que vêm em textos da web (espaço de largura zero, marca de ordem de bytes e o
/// juntor de palavras) saem nelas; o juntor de largura zero dos emojis fica, porque faz parte do próprio emoji.
public enum PasteTextFormat: String, CaseIterable, Identifiable, Sendable {
    /// O texto como foi copiado.
    case original
    /// Sem espaços sobrando: cada linha sem espaços nas pontas e com um espaço só entre as palavras, no máximo uma linha
    /// vazia entre parágrafos e nenhuma no começo ou no fim.
    case tidy
    /// Cada parágrafo numa linha só, como num texto copiado de um PDF com as linhas quebradas no meio da frase. As linhas
    /// vazias continuam separando parágrafos. Uma linha que termina em letra e hífen continua na seguinte sem espaço
    /// ("exem-" e "plo" viram "exem-plo"): o hífen fica, porque não dá para saber se ele é da palavra.
    case joinedLines
    /// Uma linha por item, cada uma com "- " na frente. O marcador que a linha já tinha ("•", "*", "1.", "2)") e a caixa de
    /// tarefa saem antes; linhas vazias não viram item.
    case bulletList
    /// Uma linha por item, cada uma com a caixa de tarefa do Markdown ("- [ ] "). Um item que já vinha marcado ("[x]")
    /// continua marcado.
    case taskList
    /// Tudo em minúsculas, pelas regras do idioma.
    case lowercase
    /// Tudo em maiúsculas, pelas regras do idioma.
    case uppercase

    public var id: String { rawValue }

    /// O texto com esta formatação.
    /// - Parameter locale: o idioma das regras de maiúsculas e minúsculas; os testes fixam um.
    public func apply(to text: String, locale: Locale = .current) -> String {
        switch self {
        case .original: text
        case .tidy: Self.tidy(text)
        case .joinedLines: Self.joinedLines(text)
        case .bulletList: Self.list(text, asTasks: false)
        case .taskList: Self.list(text, asTasks: true)
        case .lowercase: text.lowercased(with: locale)
        case .uppercase: text.uppercased(with: locale)
        }
    }

    /// O texto com esta formatação; uma formatação que o deixaria só com espaços (só havia caracteres invisíveis) não vale, e o
    /// texto fica como veio.
    public func applyKeepingNonEmpty(to text: String, locale: Locale = .current) -> String {
        let result = apply(to: text, locale: locale)
        return result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text : result
    }

    /// O texto com esta formatação aplicada só à seleção.
    ///
    /// Com uma seleção não vazia, só o trecho selecionado é formatado (com a mesma regra de `applyKeepingNonEmpty`) e o resto do
    /// texto fica como está. As quebras de linha e os espaços das pontas da seleção não entram na formatação e voltam como
    /// estavam ("segunda\n" selecionado vira "SEGUNDA\n"). As formatações de linha (`tidy`, `joinedLines`, `bulletList` e
    /// `taskList`) primeiro ampliam a seleção para as linhas inteiras; maiúsculas e minúsculas ficam com a seleção exata. Sem
    /// seleção, ou com ela vazia, vale o texto inteiro.
    /// - Parameters:
    ///   - selection: o trecho de `text` a formatar; `nil` ou vazio para o texto todo. Os limites precisam estar em fronteiras
    ///     de caractere: quem converte um `NSRange` usa a visão UTF-16 da string, em fronteiras de escalar.
    ///   - locale: o idioma das regras de maiúsculas e minúsculas; os testes fixam um.
    /// - Returns: o texto novo e a seleção nele, cobrindo o trecho formatado, sem as pontas que ficaram como estavam (o texto todo,
    ///   sem seleção). Uma seleção só de espaços não muda nada e volta como veio.
    public func apply(
        to text: String, selection: Range<String.Index>?, locale: Locale = .current
    ) -> (text: String, selection: Range<String.Index>) {
        guard let selection, !selection.isEmpty else {
            let result = applyKeepingNonEmpty(to: text, locale: locale)
            return (result, result.startIndex..<result.endIndex)
        }
        let range = formatsWholeLines ? text.lineRange(for: selection) : selection
        let piece = text[range]
        guard let first = piece.firstIndex(where: { !$0.isWhitespace }), let last = piece.lastIndex(where: { !$0.isWhitespace })
        else { return (text, selection) }
        let leading = String(piece[..<first])
        let core = String(piece[first...last])
        let trailing = String(piece[piece.index(after: last)...])

        let before = String(text[..<range.lowerBound]) + leading
        let replaced = applyKeepingNonEmpty(to: core, locale: locale)
        let result = before + replaced + trailing + text[range.upperBound...]
        // Os limites vêm de escalares inteiros, então a posição em bytes cai num limite válido mesmo se a junção fundir caracteres.
        let lower = result.utf8.index(result.utf8.startIndex, offsetBy: before.utf8.count)
        let upper = result.utf8.index(lower, offsetBy: replaced.utf8.count)
        return (result, lower..<upper)
    }

    /// As formatações que mexem em linhas inteiras.
    private var formatsWholeLines: Bool {
        switch self {
        case .tidy, .joinedLines, .bulletList, .taskList: true
        case .original, .lowercase, .uppercase: false
        }
    }

    /// O nome da formatação na linha que a oferece. As de maiúsculas e minúsculas se escrevem como o resultado, para a pessoa ver
    /// o efeito no próprio nome.
    public var title: String {
        switch self {
        case .original: "Como está"
        case .tidy: "Limpar espaços"
        case .joinedLines: "Juntar linhas"
        case .bulletList: "Lista com marcadores"
        case .taskList: "Lista de tarefas"
        case .lowercase: "minúsculas"
        case .uppercase: "MAIÚSCULAS"
        }
    }

    /// O símbolo (SF Symbols) da formatação.
    public var symbolName: String {
        switch self {
        case .original: "text.alignleft"
        case .tidy: "eraser"
        case .joinedLines: "text.justify.left"
        case .bulletList: "list.bullet"
        case .taskList: "checklist"
        case .lowercase: "textformat.size.smaller"
        case .uppercase: "textformat.size.larger"
        }
    }

    // MARK: Espaços

    private static func tidy(_ text: String) -> String {
        var output: [String] = []
        var hasBlankLine = false
        for line in lines(of: text) {
            let clean = collapsedSpaces(line)
            if clean.isEmpty {
                // Uma linha vazia só conta entre parágrafos: no começo não há o que separar.
                hasBlankLine = !output.isEmpty
            } else {
                if hasBlankLine { output.append("") }
                hasBlankLine = false
                output.append(clean)
            }
        }
        return output.joined(separator: "\n")
    }

    private static func joinedLines(_ text: String) -> String {
        var paragraphs: [String] = []
        var current = ""
        for line in lines(of: text) {
            let clean = collapsedSpaces(line)
            if clean.isEmpty {
                if !current.isEmpty { paragraphs.append(current) }
                current = ""
            } else if current.isEmpty {
                current = clean
            } else if endsWithWordHyphen(current) {
                current += clean
            } else {
                current += " " + clean
            }
        }
        if !current.isEmpty { paragraphs.append(current) }
        return paragraphs.joined(separator: "\n\n")
    }

    /// As linhas do texto. `Character.isNewline` cobre "\n", "\r", "\r\n" (um caractere só em Swift) e os separadores
    /// de linha e de parágrafo do Unicode.
    private static func lines(of text: String) -> [Substring] {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    }

    /// A linha sem os caracteres invisíveis, sem espaços nas pontas e com um espaço só onde havia vários.
    private static func collapsedSpaces(_ line: Substring) -> String {
        var result = ""
        var hasPendingSpace = false
        for character in line where !isInvisible(character) {
            if character.isWhitespace {
                hasPendingSpace = !result.isEmpty
            } else {
                if hasPendingSpace { result.append(" ") }
                hasPendingSpace = false
                result.append(character)
            }
        }
        return result
    }

    /// Espaço de largura zero (U+200B), marca de ordem de bytes (U+FEFF) e juntor de palavras (U+2060), sozinhos.
    private static func isInvisible(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first else { return false }
        return [0x200B, 0xFEFF, 0x2060].contains(scalar.value)
    }

    /// Termina numa letra seguida de hífen: a palavra continua na linha de baixo.
    private static func endsWithWordHyphen(_ text: String) -> Bool {
        text.last == "-" && text.dropLast().last?.isLetter == true
    }

    // MARK: Listas

    private static func list(_ text: String, asTasks: Bool) -> String {
        lines(of: text)
            .compactMap { line -> String? in
                let item = listItem(collapsedSpaces(line))
                guard !item.content.isEmpty else { return nil }
                guard asTasks else { return "- " + item.content }
                return (item.isDone ? "- [x] " : "- [ ] ") + item.content
            }
            .joined(separator: "\n")
    }

    /// O texto do item sem o marcador do começo ("- ", "• ", "1. ", "2) ") e sem a caixa de tarefa ("[ ]", "[x]"), pelas regras
    /// de `ListMarker` (com os marcadores extras da formatação, `lenient`).
    ///
    /// O marcador sozinho na linha é um item vazio.
    /// - Parameter line: a linha já sem espaços sobrando (`collapsedSpaces`).
    /// - Returns: o texto e se a caixa de tarefa estava marcada.
    static func listItem(_ line: String) -> (content: String, isDone: Bool) {
        guard let stripped = ListMarker.strip(line, lenient: true) else { return (line, false) }
        return (stripped.text, stripped.isDone ?? false)
    }
}
