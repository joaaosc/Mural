import Foundation

/// Onde o cursor pode parar em volta dos anexos do editor. Funções puras sobre o texto mostrado (cada anexo é um caractere U+FFFC),
/// para testar sem tela.
///
/// O cursor de um `NSTextView` tem a altura da linha em que está, e a linha de um anexo é tão alta quanto ele: colado ao anexo, o
/// cursor ficaria do tamanho da imagem, e o que se digitasse ali cairia ao lado dela. Por isso o anexo é um bloco: o cursor passa
/// por cima dele, da linha de antes para a de depois, e ⌫ ou Delete na linha vizinha apagam o bloco inteiro, em vez de juntar o
/// texto ao anexo. Só o começo do texto e um anexo sem linha depois dele (o último, sem quebra) deixam o cursor colado: não há para
/// onde ir, e é preciso poder escrever ali.
nonisolated enum EditorCaret {
    private static let attachmentCharacter: unichar = 0xFFFC
    private static let newline: unichar = 10

    /// Onde o cursor fica quando o campo propõe `proposed`: a própria posição, ou, colada a um anexo, a linha seguinte (andando para
    /// a frente) ou a anterior.
    static func location(for proposed: Int, movingForward: Bool, in text: NSString) -> Int {
        var location = proposed
        while touchesAttachment(location, in: text) {
            guard let next = movingForward ? stepForward(from: location, in: text) : stepBackward(from: location, in: text) else {
                break
            }
            location = next
        }
        return location
    }

    /// O que ⌫ apaga com o cursor no começo da linha logo abaixo de um anexo: o anexo e a quebra. `nil` fora desse caso.
    static func rangeDeletedBackward(from location: Int, in text: NSString) -> NSRange? {
        guard isNewline(at: location - 1, in: text), isAttachment(at: location - 2, in: text) else { return nil }
        return NSRange(location: location - 2, length: 2)
    }

    /// O que Delete apaga com o cursor no fim da linha logo acima de um anexo: o anexo e a quebra depois dele. `nil` fora desse caso.
    static func rangeDeletedForward(from location: Int, in text: NSString) -> NSRange? {
        guard isNewline(at: location, in: text), isAttachment(at: location + 1, in: text) else { return nil }
        return NSRange(location: location + 1, length: isNewline(at: location + 2, in: text) ? 2 : 1)
    }

    // MARK: Interno

    private static func touchesAttachment(_ location: Int, in text: NSString) -> Bool {
        location > 0 && (isAttachment(at: location, in: text) || isAttachment(at: location - 1, in: text))
    }

    /// Antes do anexo, passa por ele; depois dele, desce para a linha seguinte.
    private static func stepForward(from location: Int, in text: NSString) -> Int? {
        isAttachment(at: location, in: text) || isNewline(at: location, in: text) ? location + 1 : nil
    }

    /// Depois do anexo, passa por ele; antes dele, sobe para o fim da linha anterior.
    private static func stepBackward(from location: Int, in text: NSString) -> Int? {
        isAttachment(at: location - 1, in: text) || isNewline(at: location - 1, in: text) ? location - 1 : nil
    }

    private static func isAttachment(at index: Int, in text: NSString) -> Bool {
        index >= 0 && index < text.length && text.character(at: index) == attachmentCharacter
    }

    private static func isNewline(at index: Int, in text: NSString) -> Bool {
        index >= 0 && index < text.length && text.character(at: index) == newline
    }
}
