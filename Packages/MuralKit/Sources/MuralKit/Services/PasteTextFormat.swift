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

    /// Os marcadores de item que saem do começo da linha antes de pôr o novo.
    private static let bulletCharacters: Set<Character> = ["-", "*", "+", "•", "◦", "▪", "‣", "·", "–", "—"]

    /// O texto do item sem o marcador do começo ("- ", "• ", "1. ", "2) ") e sem a caixa de tarefa ("[ ]", "[x]").
    ///
    /// Um hífen colado ao texto não é marcador ("-5 graus" continua assim), e um número só é marcador seguido de ponto ou
    /// parêntese e de um espaço. O marcador sozinho na linha é um item vazio.
    /// - Parameter line: a linha já sem espaços sobrando (`collapsedSpaces`).
    /// - Returns: o texto e se a caixa de tarefa estava marcada.
    static func listItem(_ line: String) -> (content: String, isDone: Bool) {
        var rest = Substring(line)
        if let first = rest.first, bulletCharacters.contains(first), endsMarker(rest.dropFirst()) {
            rest = rest.dropFirst(2)
        } else {
            let digits = rest.prefix { $0.isASCII && $0.isNumber }
            let afterDigits = rest.dropFirst(digits.count)
            if !digits.isEmpty, let mark = afterDigits.first, mark == "." || mark == ")", endsMarker(afterDigits.dropFirst()) {
                rest = afterDigits.dropFirst(2)
            }
        }
        for (box, isDone) in [("[ ]", false), ("[x]", true), ("[X]", true)] where rest.hasPrefix(box) {
            let afterBox = rest.dropFirst(box.count)
            // A caixa vale sozinha ou seguida de espaço: "[x]feito" não é uma caixa.
            guard afterBox.isEmpty || afterBox.first == " " else { break }
            return (String(afterBox.drop { $0 == " " }), isDone)
        }
        return (String(rest), false)
    }

    /// O que vem depois de um marcador o confirma: um espaço ou o fim da linha.
    private static func endsMarker(_ rest: Substring) -> Bool {
        rest.isEmpty || rest.first == " "
    }
}
