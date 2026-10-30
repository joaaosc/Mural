import Foundation

/// Monta os endereços `tel:` e `mailto:` dos contatos. Funções puras, para serem conferidas sem abrir nada.
nonisolated enum ContactDialing {
    /// Caracteres que um número de telefone pode ter num `tel:`: dígitos ASCII, `+`, `*`, `#` e as pausas `,` e `;`.
    private static let dialable: Set<Character> = ["+", "*", "#", ",", ";"]

    /// A cadeia de discagem de um telefone, mantendo só o que é discável e parando na primeira letra: "3333-4444 ramal 12"
    /// vira "33334444", para o ramal não ser discado como parte do número. `nil` se não sobra nada.
    static func dialString(_ phone: String) -> String? {
        var result = ""
        for character in phone {
            if character.isLetter { break }
            if let ascii = character.asciiValue, (48...57).contains(ascii) || dialable.contains(character) {
                result.append(character)
            }
        }
        return result.isEmpty ? nil : result
    }

    /// O `tel:` do telefone, ou `nil` se não há o que discar.
    static func telURL(_ phone: String) -> URL? {
        dialString(phone).flatMap { URL(string: "tel:\($0)") }
    }

    /// O `mailto:` do endereço, com o texto escapado, ou `nil` se o endereço está em branco.
    static func mailURL(_ address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let escaped = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "mailto:\(escaped)")
    }
}
