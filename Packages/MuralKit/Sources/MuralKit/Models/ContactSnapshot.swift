import Foundation

/// Um valor com a etiqueta que a pessoa deu a ele no cartão de contato, como "casa" ou "trabalho".
public struct LabeledValue: Codable, Hashable, Sendable {
    /// Etiqueta já localizada, como veio do vCard; `nil` quando não tinha.
    public var label: String?
    public var value: String

    public init(label: String? = nil, value: String) {
        self.label = label
        self.value = value
    }

    /// Só `value` é obrigatório; a etiqueta assume `nil` quando falta.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        value = try container.decode(String.self, forKey: .value)
    }
}

/// Último estado conhecido de uma pessoa ou empresa lida de um vCard copiado, guardado no cartão.
///
/// O Mural nunca consulta o app Contatos: o que está aqui veio do próprio vCard e não é atualizado depois.
public struct ContactSnapshot: Codable, Hashable, Sendable {
    public var givenName: String
    public var familyName: String
    public var organization: String?
    public var phones: [LabeledValue]
    public var emails: [LabeledValue]
    /// Nome do arquivo da foto reduzida guardada pelo Mural (fora da pasta de itens). Parte local de cada Mac.
    public var thumbnailFile: String?

    public init(
        givenName: String = "",
        familyName: String = "",
        organization: String? = nil,
        phones: [LabeledValue] = [],
        emails: [LabeledValue] = [],
        thumbnailFile: String? = nil
    ) {
        self.givenName = givenName
        self.familyName = familyName
        self.organization = organization
        self.phones = phones
        self.emails = emails
        self.thumbnailFile = thumbnailFile
    }

    /// Todos os campos são opcionais ao ler, para o formato poder ganhar campos sem invalidar murais já gravados.
    /// Chaves desconhecidas são ignoradas.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        givenName = try container.decodeIfPresent(String.self, forKey: .givenName) ?? ""
        familyName = try container.decodeIfPresent(String.self, forKey: .familyName) ?? ""
        organization = try container.decodeIfPresent(String.self, forKey: .organization)
        phones = try container.decodeIfPresent([LabeledValue].self, forKey: .phones) ?? []
        emails = try container.decodeIfPresent([LabeledValue].self, forKey: .emails) ?? []
        thumbnailFile = try container.decodeIfPresent(String.self, forKey: .thumbnailFile)
    }

    private static let fallbackName = "Contato"

    /// Nome e sobrenome juntos; sem eles, a organização; sem nada, "Contato".
    public var displayName: String {
        let person = [givenName, familyName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !person.isEmpty { return person }
        if let organization = organization?.trimmingCharacters(in: .whitespacesAndNewlines), !organization.isEmpty {
            return organization
        }
        return Self.fallbackName
    }

    /// Até duas iniciais, em maiúsculas, para o círculo sem foto: a do nome e a do sobrenome, ou as duas primeiras palavras do
    /// nome de exibição. Vazio só se o nome de exibição não tem letras.
    public var initials: String {
        let given = givenName.trimmingCharacters(in: .whitespacesAndNewlines)
        let family = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let letters: [Character]
        if let first = given.first, let second = family.first {
            letters = [first, second]
        } else {
            letters = displayName.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first)
        }
        return String(letters).uppercased()
    }

    /// O primeiro telefone, se houver.
    public var primaryPhone: String? { phones.first?.value }

    /// O primeiro e-mail, se houver.
    public var primaryEmail: String? { emails.first?.value }

    /// Chave para reconhecer a mesma pessoa copiada duas vezes: o nome de exibição em minúsculas mais o primeiro e-mail ou, na
    /// falta dele, o primeiro telefone.
    public var dedupeKey: String {
        let reach = (primaryEmail ?? primaryPhone ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(displayName.lowercased())|\(reach)"
    }
}
