import Foundation

/// O marcador de item no começo de uma linha de texto simples, lido num lugar só para o leitor de listas
/// (`ChecklistParser`) e para a formatação "lista" (`PasteTextFormat`).
///
/// Marcadores: `- `, `* `, `+ `, `• `, `◦ ` e `▪ `, e números de um a três dígitos seguidos de ponto ou parêntese (`1. `,
/// `12) `). Depois do marcador vale um espaço, uma tabulação ou outro espaço em branco (textos copiados do Word ou de PDFs), e todo
/// o espaço que vem em seguida sai. Um hífen colado ao texto não é marcador ("-5 graus"), `1-` também não, e um número de quatro
/// dígitos é um ano ("2024. Foi um ano"). Um número seguido de "de", "do" ou "da" é uma data ("12. de abril"), não um item. A caixa
/// de tarefa (`[ ]`, `[x]`, `[X]`) vale com ou sem marcador na frente.
enum ListMarker {
    private static let bullets: Set<Character> = ["-", "*", "+", "•", "◦", "▪"]
    /// Marcadores que só a formatação de lista tira (`lenient`): os travessões abrem falas de diálogo, então não fazem uma lista.
    private static let lenientBullets: Set<Character> = ["‣", "·", "–", "—"]
    /// Palavras que, depois de "N. ", mostram uma data ("12. de abril") e não um item.
    private static let dateWords = ["de ", "do ", "da "]

    /// O texto da linha sem o marcador do começo e sem a caixa de tarefa.
    ///
    /// O marcador sozinho na linha dá um texto vazio.
    /// - Parameters:
    ///   - line: a linha já sem espaços nas pontas.
    ///   - lenient: aceita também `‣`, `·`, `–` e `—` como marcador (a formatação "lista" os tira; o leitor de listas não os conta).
    /// - Returns: o texto e se a caixa de tarefa estava marcada (`nil` quando não havia caixa); `nil` quando a linha não tem
    ///   marcador nem caixa.
    static func strip(_ line: String, lenient: Bool = false) -> (text: String, isDone: Bool?)? {
        var rest = Substring(line)
        var hasMarker = false
        if let first = rest.first, bullets.contains(first) || (lenient && lenientBullets.contains(first)),
            endsMarker(rest.dropFirst())
        {
            rest = rest.dropFirst().drop { $0.isWhitespace }
            hasMarker = true
        } else {
            let digits = rest.prefix { $0.isASCII && $0.isNumber }
            let afterDigits = rest.dropFirst(digits.count)
            if (1...3).contains(digits.count), let mark = afterDigits.first, mark == "." || mark == ")",
                endsMarker(afterDigits.dropFirst())
            {
                let text = afterDigits.dropFirst().drop { $0.isWhitespace }
                if !dateWords.contains(where: { text.lowercased().hasPrefix($0) }) {
                    rest = text
                    hasMarker = true
                }
            }
        }
        for (box, isDone) in [("[ ]", false), ("[x]", true), ("[X]", true)] where rest.hasPrefix(box) {
            let afterBox = rest.dropFirst(box.count)
            // A caixa vale sozinha ou seguida de espaço: "[x]feito" não é uma caixa.
            guard afterBox.isEmpty || afterBox.first?.isWhitespace == true else { break }
            return (String(afterBox.drop { $0.isWhitespace }), isDone)
        }
        return hasMarker ? (String(rest), nil) : nil
    }

    /// O que vem depois de um marcador o confirma: um espaço em branco ou o fim da linha.
    private static func endsMarker(_ rest: Substring) -> Bool {
        rest.isEmpty || rest.first?.isWhitespace == true
    }
}
