import Foundation

/// Regra do nome de um mural. O nome vira nome de arquivo (a cópia na pasta Mural do iCloud Drive, o "Salvar uma Cópia…"), então
/// ele não aceita o que o macOS recusa num nome de arquivo: `/`, que separa pastas no disco, e `:`, que o Finder recusa por ser o
/// separador antigo do Mac. Quebras de linha e outros caracteres invisíveis de controle também ficam de fora.
public enum BoardName {
    /// Nome usado quando o pedido fica vazio.
    public static let untitled = "Mural sem título"

    /// O que impede um nome de ser usado.
    public enum Issue: Equatable, Sendable {
        /// `:` ou `/`.
        case forbiddenCharacter(Character)
        /// Quebra de linha, tabulação ou outro caractere invisível de controle.
        case controlCharacter

        /// A frase mostrada embaixo do campo do nome.
        public var message: String {
            switch self {
            case .forbiddenCharacter(let character):
                "O nome do mural não pode ter “\(character)”, que o macOS não aceita em nomes de arquivo."
            case .controlCharacter:
                "O nome do mural não pode ter quebras de linha nem caracteres invisíveis."
            }
        }
    }

    /// O primeiro problema do nome, na ordem do texto; `nil` se ele pode ser usado.
    public static func issue(in name: String) -> Issue? {
        for scalar in name.unicodeScalars {
            if scalar == ":" || scalar == "/" { return .forbiddenCharacter(Character(scalar)) }
            if scalar.properties.generalCategory == .control { return .controlCharacter }
        }
        return nil
    }

    /// O nome com `:` e `/` trocados por `-`, sem caracteres de controle e sem espaços nas pontas; `untitled` se nada sobrar. Serve
    /// para o nome que não passou por um campo, como o de um pacote importado ou o de um mural salvo antes desta regra.
    public static func sanitized(_ name: String) -> String {
        let scalars = name.unicodeScalars.compactMap { scalar -> Unicode.Scalar? in
            if scalar.properties.generalCategory == .control { return nil }
            return scalar == ":" || scalar == "/" ? "-" : scalar
        }
        let cleaned = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? untitled : cleaned
    }
}
